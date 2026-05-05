package provider

import (
	"errors"
	"time"
)

type VerifierAdapterMode string

const (
	VerifierAdapterContract   VerifierAdapterMode = "contract"
	VerifierAdapterProduction VerifierAdapterMode = "production"
)

var (
	ErrUnknownVerifierAdapterMode   = errors.New("unknown verifier adapter mode")
	ErrProductionAdapterConfig      = errors.New("production adapter config missing")
	ErrProductionAdapterUnavailable = errors.New("production adapter unavailable")
)

type VerifierAdapterConfig struct {
	Mode         VerifierAdapterMode
	SharedSecret string
	Audience     string
	Now          func() time.Time

	ProductionTrustAnchors []string
	ProductionAudience     string
}

func NewProofVerifierAdapter(config VerifierAdapterConfig) (ProofVerifier, error) {
	switch config.Mode {
	case VerifierAdapterContract:
		return NewContractProofVerifier(ContractProofConfig{
			SharedSecret: config.SharedSecret,
			Audience:     config.Audience,
			Now:          config.Now,
		}), nil
	case VerifierAdapterProduction:
		if len(config.ProductionTrustAnchors) == 0 || config.ProductionAudience == "" {
			return nil, ErrProductionAdapterConfig
		}
		return nil, ErrProductionAdapterUnavailable
	default:
		return nil, ErrUnknownVerifierAdapterMode
	}
}
