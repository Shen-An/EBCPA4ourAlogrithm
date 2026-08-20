package apklist

import (
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// SmartContract provides functions for managing witness information
type SmartContract struct {
	contractapi.Contract
}

// WitnessEntity represents storage format (VC, CS, unrevoked)
type WitnessEntity struct {
	VC        string `json:"vc"`
	CS        string `json:"cs"`
	Unrevoked bool   `json:"unrevoked"`
}

// Store stores (VC, CS) for DID (only Authority)
func (s *SmartContract) Store(ctx contractapi.TransactionContextInterface, did string, vc string, cs string) error {
	if err := ctx.GetClientIdentity().AssertAttributeValue("apklist.creator", "true"); err != nil {
		return fmt.Errorf("invoker not authorized (requires apklist.creator=true)")
	}

	entity := WitnessEntity{VC: vc, CS: cs, Unrevoked: true}
	b, err := json.Marshal(entity)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(did, b)
}

// Query returns "VC|CS" if not revoked; otherwise returns "_|_".
// NOTE: fabric-contract-api-go allows at most one non-error return value,
// so (VC, CS) are joined into a single "VC|CS" string.
func (s *SmartContract) Query(ctx contractapi.TransactionContextInterface, did string) (string, error) {
	b, err := ctx.GetStub().GetState(did)
	if err != nil {
		return "", fmt.Errorf("failed to read from world state: %v", err)
	}
	if b == nil {
		return "_|_", nil
	}

	var entity WitnessEntity
	if err := json.Unmarshal(b, &entity); err != nil {
		return "", err
	}

	if entity.Unrevoked {
		return entity.VC + "|" + entity.CS, nil
	}
	return "_|_", nil
}

// Update marks DID revoked (unrevoked=false) (only Authority)
func (s *SmartContract) Update(ctx contractapi.TransactionContextInterface, did string) error {
	if err := ctx.GetClientIdentity().AssertAttributeValue("apklist.creator", "true"); err != nil {
		return fmt.Errorf("invoker not authorized (requires apklist.creator=true)")
	}

	b, err := ctx.GetStub().GetState(did)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if b == nil {
		// strict but safe: treat missing as no-op
		return nil
	}

	var entity WitnessEntity
	if err := json.Unmarshal(b, &entity); err != nil {
		return err
	}

	if entity.Unrevoked {
		entity.Unrevoked = false
		nb, err := json.Marshal(entity)
		if err != nil {
			return err
		}
		return ctx.GetStub().PutState(did, nb)
	}

	return nil
}

