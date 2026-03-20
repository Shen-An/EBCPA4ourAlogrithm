'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

const helper = require('./helper');

/**
 * Workload module for the benchmark round.
 */
class RetrieveWorkload extends WorkloadModuleBase {
    /**
     * Initializes the workload module instance.
     */
    constructor() {
        super();
        this.txIndex = 0;
        this.limitIndex = 0;
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);

        this.limitIndex = this.roundArguments.assets;
        await helper.uploadWitness(this.sutAdapter, this.workerIndex, this.roundArguments);
    }

    /**
     * Assemble TXs for the round.
     * @return {Promise<TxStatus[]>}
     */
    async submitTransaction() {
        this.txIndex++;
        const id = 'ID' + this.workerIndex + '_' + this.txIndex.toString();

        const args = {
            contractId: this.roundArguments.contractId || 'apklist',
            contractVersion: 'v1',
            contractFunction: 'Query',
            contractArguments: [id],
            timeout: 30,
            readOnly: true
        };

        if (this.txIndex === this.limitIndex) {
            this.txIndex = 0;
        }

        const res = await this.sutAdapter.sendRequests(args);

        // Query 期望返回两个值 (VC, CS)。不同 connector 可能把返回放在 result/response/payload。
        // 常见是返回 JSON 字符串 {"vc":"...","cs":"..."} 或 "vc|cs"。
        const r0 = Array.isArray(res) ? res[0] : res;
        const payload = r0?.result ?? r0?.response ?? r0?.payload;
        if (payload) {
            try {
                const s = Buffer.isBuffer(payload) ? payload.toString('utf8') : String(payload);
                if (s.startsWith('{')) {
                    const obj = JSON.parse(s);
                    void obj?.vc;
                    void obj?.cs;
                } else if (s.includes('|')) {
                    const [vc, cs] = s.split('|', 2);
                    void vc;
                    void cs;
                }
            } catch (e) {
                // ignore
            }
        }
    }
}

/**
 * Create a new instance of the workload module.
 * @return {WorkloadModuleInterface}
 */
function createWorkloadModule() {
    return new RetrieveWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;