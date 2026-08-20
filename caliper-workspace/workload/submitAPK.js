'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

function randomWitnessPart() {
    // simple deterministic-ish payload to control size
    return 'W' + Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2);
}

class UploadWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        const id = 'ID' + this.workerIndex + '_' + this.txIndex.toString();
        const vc = randomWitnessPart();
        const cs = randomWitnessPart();

        const args = {
            contractId: 'apklist',
            contractVersion: 'v1',
            contractFunction: 'Store',
            contractArguments: [id, vc, cs],
            timeout: 30
        };

        await this.sutAdapter.sendRequests(args);
    }
}

function createWorkloadModule() {
    return new UploadWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;