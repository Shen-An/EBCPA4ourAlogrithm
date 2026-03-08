#!/usr/bin/env bash
set -eu

# Try to enable pipefail when supported (bash/zsh). Ignore on /bin/sh (dash).
(set -o pipefail) 2>/dev/null && set -o pipefail || true

# One-click deploy script for apklist chaincode using Fabric lifecycle.
# - Brings up test-network with Fabric CA (so we can create identities with attributes)
# - Creates channel mychannel
# - Packages/installs/approves/commits apklist chaincode as name "apklist"
#
# Prereqs:
# - docker running
# - fabric-samples present under /root/fabric/fabric-samples
# - chaincode source at /root/EBCPA/chaincode-go

ROOT_DIR="/root"
FABRIC_SAMPLES="${ROOT_DIR}/fabric/fabric-samples"
TEST_NETWORK="${FABRIC_SAMPLES}/test-network"
CC_PATH="${ROOT_DIR}/EBCPA/chaincode-go"
CC_NAME="apklist"
CC_LABEL="apklist_1"
CC_VERSION="1.0"
CC_SEQUENCE="1"
CHANNEL_NAME="mychannel"

# If you want to use a different user name for benchmarking, change it here.
# This script will register/enroll a user under Org1 with attribute apklist.creator=true
BENCH_USER="creator1"
BENCH_USER_SECRET="creator1pw"

export FABRIC_CFG_PATH="${FABRIC_SAMPLES}/config"
export PATH="${FABRIC_SAMPLES}/bin:${PATH}"

ORDERER_CA="${TEST_NETWORK}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORG1_CA_TLS_CERT="${TEST_NETWORK}/organizations/fabric-ca/org1/tls-cert.pem"
ORG1_CA_URL="https://localhost:7054"

say() { printf "\n==> %s\n" "$*"; }

setGlobalsOrg1() {
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID=Org1MSP
  export CORE_PEER_MSPCONFIGPATH="${TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS=localhost:7051
  export CORE_PEER_TLS_ROOTCERT_FILE="${TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
}

setGlobalsOrg2() {
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID=Org2MSP
  export CORE_PEER_MSPCONFIGPATH="${TEST_NETWORK}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
  export CORE_PEER_ADDRESS=localhost:9051
  export CORE_PEER_TLS_ROOTCERT_FILE="${TEST_NETWORK}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing file: $1" >&2
    exit 1
  fi
}

say "Sanity checks"
require_file "${TEST_NETWORK}/network.sh"
require_file "${FABRIC_SAMPLES}/bin/peer"
require_file "${FABRIC_SAMPLES}/bin/fabric-ca-client"
require_file "${CC_PATH}/go.mod"

say "Bringing network down (clean)"
cd "${TEST_NETWORK}"
./network.sh down || true

say "Bringing network up with Fabric CA and creating channel ${CHANNEL_NAME}"
./network.sh up -ca
./network.sh createChannel -c "${CHANNEL_NAME}"

say "Register/enroll benchmark identity with attribute apklist.creator=true (Org1 CA)"
# Enroll CA admin for org1 (writes MSP material under organizations/fabric-ca/org1)
export FABRIC_CA_CLIENT_HOME="${TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/"

# Ensure org1 CA TLS cert exists (created by -ca network)
require_file "${ORG1_CA_TLS_CERT}"

# Enroll the CA admin (admin:adminpw is default in test-network CA)
fabric-ca-client enroll -u "${ORG1_CA_URL}" -u "https://admin:adminpw@localhost:7054" --tls.certfiles "${ORG1_CA_TLS_CERT}"

# Register user with attribute; if already registered, ignore error
set +e
fabric-ca-client register \
  --id.name "${BENCH_USER}" \
  --id.secret "${BENCH_USER_SECRET}" \
  --id.type client \
  --id.attrs "apklist.creator=true:ecert" \
  -u "${ORG1_CA_URL}" \
  --tls.certfiles "${ORG1_CA_TLS_CERT}"
set -e

# Enroll benchmark user into standard users directory
BENCH_USER_HOME="${TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/users/${BENCH_USER}@org1.example.com"
mkdir -p "${BENCH_USER_HOME}"
export FABRIC_CA_CLIENT_HOME="${BENCH_USER_HOME}"

fabric-ca-client enroll \
  -u "https://${BENCH_USER}:${BENCH_USER_SECRET}@localhost:7054" \
  --tls.certfiles "${ORG1_CA_TLS_CERT}"

say "Packaging chaincode ${CC_NAME} from ${CC_PATH}"
cd "${TEST_NETWORK}"
rm -f "${CC_NAME}.tar.gz"
peer lifecycle chaincode package "${CC_NAME}.tar.gz" --path "${CC_PATH}" --lang golang --label "${CC_LABEL}"

say "Installing chaincode on Org1"
setGlobalsOrg1
peer lifecycle chaincode install "${CC_NAME}.tar.gz"

say "Installing chaincode on Org2"
setGlobalsOrg2
peer lifecycle chaincode install "${CC_NAME}.tar.gz"

say "Query installed to extract PACKAGE_ID"
setGlobalsOrg1
PKG_LINE=$(peer lifecycle chaincode queryinstalled | sed -n "s/^Package ID: \(.*\), Label: ${CC_LABEL}$/\1/p" | head -n 1)
if [[ -z "${PKG_LINE}" ]]; then
  echo "Failed to find Package ID for label ${CC_LABEL}. Output was:" >&2
  peer lifecycle chaincode queryinstalled >&2
  exit 1
fi
PACKAGE_ID="${PKG_LINE}"

echo "PACKAGE_ID=${PACKAGE_ID}"

say "Approving chaincode definition for Org1"
setGlobalsOrg1
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" \
  -C "${CHANNEL_NAME}" -n "${CC_NAME}" -v "${CC_VERSION}" --sequence "${CC_SEQUENCE}" \
  --package-id "${PACKAGE_ID}"

say "Approving chaincode definition for Org2"
setGlobalsOrg2
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" \
  -C "${CHANNEL_NAME}" -n "${CC_NAME}" -v "${CC_VERSION}" --sequence "${CC_SEQUENCE}" \
  --package-id "${PACKAGE_ID}"

say "Checking commit readiness"
setGlobalsOrg1
peer lifecycle chaincode checkcommitreadiness \
  -C "${CHANNEL_NAME}" -n "${CC_NAME}" -v "${CC_VERSION}" --sequence "${CC_SEQUENCE}" --output json

say "Committing chaincode definition"
setGlobalsOrg1
peer lifecycle chaincode commit \
  -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" \
  -C "${CHANNEL_NAME}" -n "${CC_NAME}" -v "${CC_VERSION}" --sequence "${CC_SEQUENCE}" \
  --peerAddresses localhost:7051 \
  --tlsRootCertFiles "${TEST_NETWORK}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt" \
  --peerAddresses localhost:9051 \
  --tlsRootCertFiles "${TEST_NETWORK}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

say "Query committed"
peer lifecycle chaincode querycommitted -C "${CHANNEL_NAME}" -n "${CC_NAME}"

say "Done. Benchmark identity artifacts (Org1)"
echo "User MSP at: ${BENCH_USER_HOME}/msp"
echo "Signcert: ${BENCH_USER_HOME}/msp/signcerts/cert.pem"
echo "Keystore: ${BENCH_USER_HOME}/msp/keystore/"

echo
say "Next step: update Caliper networkConfig.json to point to ${BENCH_USER}@org1.example.com cert/key (with apklist.creator=true)"
