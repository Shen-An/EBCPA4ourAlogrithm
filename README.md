# Our EBCPA protocol

This workspace (`/root/EBCPA4ourAlogrithm`) contains the Go-based Fabric chaincode implementation and the Caliper benchmark assets used to reproduce the performance results.

## 1. Go-based Chaincode (Hyperledger Fabric)

### 1.1 Prerequisites

- Docker + Docker Compose
- Go (for chaincode build)
- Node.js + npm/npx (for Caliper)

### 1.2 One-click deploy (network + identity + chaincode)

```bash
bash /root/EBCPA4ourAlogrithm/deploy_apklist_lifecycle.sh
```

This script will:
- bring up `fabric-samples/test-network` with Fabric CA (`-ca`)
- create channel `mychannel`
- register/enroll an Org1 client identity with attribute `apklist.creator=true`
- package/install/approve/commit the chaincode as `apklist`

### 1.3 One-click benchmark (Caliper)

```bash
bash /root/EBCPA4ourAlogrithm/run_benchmark.sh
```

The final report will be generated at:
- `/root/EBCPA4ourAlogrithm/caliper-workspace/report.html`

## 2. Caliper Workloads

Benchmark rounds are defined in:
- `caliper-workspace/benchmarks/myAPKBenchmark.yaml`

Workload modules are under:
- `caliper-workspace/workload/`

Current contract functions used by the workloads:
- `Upload(id, W)`
- `Retrieve(id)`
- `Revoke(id)`

---

## Appendix: Full Environment Check Report

### 1. System Information

```text
Distributor ID: Ubuntu
Description:    Ubuntu 22.04.5 LTS
Release:        22.04
Codename:       jammy
Kernel:         Linux CHINAMI-MMJLF0R 6.6.87.2-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC Thu Jun  5 18:30:46 UTC 2025 x86_64
Workspace:      /root/EBCPA4ourAlogrithm
```

### 2. Docker / Docker Compose

```text
Docker version 29.2.1, build a5c7197
Docker Compose version v5.0.2
```

### 3. Go

```text
go version go1.17 linux/amd64
GOPATH="/root/go"
GOROOT="/usr/local/go"
```

### 4. Node.js / npm / npx

```text
node: v10.22.1
npm:  6.14.6
npx:  10.2.2
```

### 5. Caliper (core for the paper)

```text
v0.4.0
```
### 6.Hyperledger Fabric
Version: 2.1.0
