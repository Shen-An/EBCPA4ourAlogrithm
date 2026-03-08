#!/usr/bin/env bash
set -eu

# Try to enable pipefail when supported.
(set -o pipefail) 2>/dev/null && set -o pipefail || true

ROOT_DIR="/root"
PROJECT_DIR="${ROOT_DIR}/EBCPA"
CALIPER_DIR="${PROJECT_DIR}/caliper-workspace"
NETWORK_CFG="${CALIPER_DIR}/networks/networkConfig.json"
BENCH_CFG="${CALIPER_DIR}/benchmarks/myAPKBenchmark.yaml"
REPORT_FILE="${CALIPER_DIR}/report.html"

# Deployed benchmark identity (created by deploy_apklist_lifecycle.sh)
USER_NAME="creator1"
USER_ORG_DOMAIN="org1.example.com"
USER_ID="${USER_NAME}@${USER_ORG_DOMAIN}"
USER_DIR="${ROOT_DIR}/fabric/fabric-samples/test-network/organizations/peerOrganizations/${USER_ORG_DOMAIN}/users/${USER_ID}"
USER_CERT="${USER_DIR}/msp/signcerts/cert.pem"
USER_KEYSTORE_DIR="${USER_DIR}/msp/keystore"

say() { printf "\n==> %s\n" "$*"; }

timestamp() { date '+%Y%m%d-%H%M%S'; }

say "Sanity checks"
if [[ ! -d "${CALIPER_DIR}" ]]; then
  echo "Missing caliper workspace: ${CALIPER_DIR}" >&2
  exit 1
fi
if [[ ! -f "${NETWORK_CFG}" ]]; then
  echo "Missing network config: ${NETWORK_CFG}" >&2
  exit 1
fi
if [[ ! -f "${BENCH_CFG}" ]]; then
  echo "Missing benchmark config: ${BENCH_CFG}" >&2
  exit 1
fi
if [[ ! -f "${USER_CERT}" ]]; then
  echo "Missing user cert: ${USER_CERT}" >&2
  echo "Run ${PROJECT_DIR}/deploy_apklist_lifecycle.sh first." >&2
  exit 1
fi
if [[ ! -d "${USER_KEYSTORE_DIR}" ]]; then
  echo "Missing user keystore dir: ${USER_KEYSTORE_DIR}" >&2
  exit 1
fi

say "Detecting private key file under keystore"
KEY_FILE=$(ls -1 "${USER_KEYSTORE_DIR}"/*_sk 2>/dev/null | head -n 1 || true)
if [[ -z "${KEY_FILE}" ]]; then
  # some CA configs use different naming; fallback to first file
  KEY_FILE=$(ls -1 "${USER_KEYSTORE_DIR}"/* 2>/dev/null | head -n 1 || true)
fi
if [[ -z "${KEY_FILE}" ]]; then
  echo "No private key found under: ${USER_KEYSTORE_DIR}" >&2
  exit 1
fi

# Convert to the relative paths Caliper config uses.
# NOTE: networkConfig.json is under caliper-workspace/networks, so paths are resolved relative to caliper-workspace.
# The real fabric-samples location is /root/fabric/fabric-samples, i.e. ../../fabric/fabric-samples from caliper-workspace.
REL_CERT_PATH="../../fabric/fabric-samples/test-network/organizations/peerOrganizations/${USER_ORG_DOMAIN}/users/${USER_ID}/msp/signcerts/cert.pem"
REL_KEY_PATH="../../fabric/fabric-samples/test-network/organizations/peerOrganizations/${USER_ORG_DOMAIN}/users/${USER_ID}/msp/keystore/$(basename "${KEY_FILE}")"

say "Updating Caliper networkConfig.json with current cert/key path"
python3 - <<PY
import json
p = "${NETWORK_CFG}"
with open(p,'r') as f:
    d = json.load(f)
client = d['clients']['creator1@org1.example.com']['client']
client['clientSignedCert']['path'] = "${REL_CERT_PATH}"
client['clientPrivateKey']['path'] = "${REL_KEY_PATH}"
with open(p,'w') as f:
    json.dump(d, f, indent=4)
PY

say "Installing npm dependencies (if needed)"
cd "${CALIPER_DIR}"
if [[ ! -d node_modules ]]; then
  npm install
fi

say "Preparing report file"
if [[ -f "${REPORT_FILE}" ]]; then
  BACKUP="${REPORT_FILE}.$(timestamp).bak"
  cp -f "${REPORT_FILE}" "${BACKUP}"
  rm -f "${REPORT_FILE}"
  echo "Backed up previous report to: ${BACKUP}"
fi

say "Running Caliper benchmark (gateway mode)"
# Caliper v0.4.0 does NOT expose a --gateway flag on the launch command.
# Gateway mode is controlled via Caliper config keys, which can be set by env vars.
# For Fabric SDK 2.x this must be enabled, otherwise the connector throws.
export CALIPER_FABRIC_GATEWAY_ENABLED=true

set +e
npx caliper launch manager \
  --caliper-workspace . \
  --caliper-networkconfig networks/networkConfig.json \
  --caliper-benchconfig benchmarks/myAPKBenchmark.yaml
RES=$?
set -e

say "Finished (exit code: ${RES})"
if [[ ${RES} -ne 0 ]]; then
  echo "Benchmark failed (exit code ${RES})." >&2
  echo "If report.html exists, it may be partial and should not be trusted." >&2
  if [[ -f "${REPORT_FILE}" ]]; then
    echo "Partial report: ${REPORT_FILE}" >&2
  fi
  exit ${RES}
fi

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "Benchmark succeeded but report.html not found at: ${REPORT_FILE}" >&2
  exit 2
fi

echo "Report: ${REPORT_FILE}"
exit ${RES}
