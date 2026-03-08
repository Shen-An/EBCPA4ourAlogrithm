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

// WitnessEntity represents the storage format in the paper (Entity{W, unrevoked})
type WitnessEntity struct {
	W         string `json:"W"`
	Unrevoked bool   `json:"unrevoked"`
}

// Upload stores the witness information for UD/AP_i.
// Only NM/Authority can invoke (mapped to attribute apklist.creator=true).
func (s *SmartContract) Upload(ctx contractapi.TransactionContextInterface, udOrAPi string, w string) error {
	if err := ctx.GetClientIdentity().AssertAttributeValue("apklist.creator", "true"); err != nil {
		return fmt.Errorf("invoker not authorized (requires apklist.creator=true)")
	}

	entity := WitnessEntity{W: w, Unrevoked: true}
	b, err := json.Marshal(entity)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(udOrAPi, b)
}

// Retrieve returns witness information if not revoked; otherwise returns "_".
func (s *SmartContract) Retrieve(ctx contractapi.TransactionContextInterface, udOrAPi string) (string, error) {
	b, err := ctx.GetStub().GetState(udOrAPi)
	if err != nil {
		return "", fmt.Errorf("failed to read from world state: %v", err)
	}
	if b == nil {
		return "_", nil
	}

	var entity WitnessEntity
	if err := json.Unmarshal(b, &entity); err != nil {
		return "", err
	}

	if entity.Unrevoked {
		return entity.W, nil
	}
	return "_", nil
}

// Revoke marks UD/AP_i as revoked (unrevoked=false).
// Only NM/Authority can invoke (mapped to attribute apklist.creator=true).
func (s *SmartContract) Revoke(ctx contractapi.TransactionContextInterface, udOrAPi string) error {
	if err := ctx.GetClientIdentity().AssertAttributeValue("apklist.creator", "true"); err != nil {
		return fmt.Errorf("invoker not authorized (requires apklist.creator=true)")
	}

	b, err := ctx.GetStub().GetState(udOrAPi)
	if err != nil {
		return fmt.Errorf("failed to read from world state: %v", err)
	}
	if b == nil {
		// match paper logic: if not present, do nothing (or return error). Here: error to surface inconsistent test.
		return fmt.Errorf("the witness %s does not exist", udOrAPi)
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
		return ctx.GetStub().PutState(udOrAPi, nb)
	}

	return nil
}

// --- Backward-compatible APIs (optional) ---

// Submit is kept for compatibility with existing benchmarks.
func (s *SmartContract) Submit(ctx contractapi.TransactionContextInterface, hash string, apk1 string, apk2 string) error {
	// store apk1|apk2 as a combined witness string for legacy call sites
	return s.Upload(ctx, hash, fmt.Sprintf("%s|%s", apk1, apk2))
}

// Check is kept for compatibility with existing benchmarks.
func (s *SmartContract) Check(ctx contractapi.TransactionContextInterface, hash string) (bool, error) {
	w, err := s.Retrieve(ctx, hash)
	if err != nil {
		return false, err
	}
	return w != "_", nil
}

