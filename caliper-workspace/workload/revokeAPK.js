'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

const helper = require('./helper');

class RevokeWorkload extends WorkloadModuleBase {
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

    async submitTransaction() {
        this.txIndex++;
        const id = 'ID' + this.workerIndex + '_' + this.txIndex.toString();

        const args = {
            contractId: 'apklist',
            contractVersion: 'v1',
            contractFunction: 'Revoke',
            contractArguments: [id],
            timeout: 30
        };

        if (this.txIndex === this.limitIndex) {
            this.txIndex = 0;
        }

        await this.sutAdapter.sendRequests(args);
    }
}

function createWorkloadModule() {
    return new RevokeWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;