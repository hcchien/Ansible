package hostedissuer

import (
	"context"
	"errors"
	"time"

	"github.com/trisaura/ansible_issuer/internal/vc"
)

type KeyManager struct {
	store Store
	kms   vc.KMSClient
	now   func() time.Time
}

func NewKeyManager(store Store, kms vc.KMSClient, now func() time.Time) *KeyManager {
	if now == nil {
		now = time.Now
	}
	return &KeyManager{store: store, kms: kms, now: now}
}

// RegisterHSMKey validates a pre-provisioned tenant-specific Cloud KMS key.
// Key creation/IAM is performed by the deployment service account; this API
// never accepts or handles private key material.
func (m *KeyManager) RegisterHSMKey(ctx context.Context, tenantID, keyVersion string, version int64) (SigningKey, error) {
	if tenantID == "" || keyVersion == "" || version < 1 || m.kms == nil {
		return SigningKey{}, ErrDelegationInvalid
	}
	publicPEM, algorithm, protection, err := m.kms.PublicKey(ctx, keyVersion)
	if err != nil {
		return SigningKey{}, err
	}
	if algorithm != "EC_SIGN_ED25519" || (protection != "HSM" && protection != "HSM_SINGLE_TENANT") {
		return SigningKey{}, errors.New("hosted issuer key must be HSM EC_SIGN_ED25519")
	}
	id, err := randomControlPlaneID("key")
	if err != nil {
		return SigningKey{}, err
	}
	key := SigningKey{ID: id, TenantID: tenantID, KMSKeyVersion: keyVersion, PublicKeyPEM: publicPEM, Algorithm: algorithm, ProtectionLevel: protection, State: "proposed", Version: version, CreatedAt: m.now().UTC()}
	if err := m.store.PutSigningKey(tenantID, key); err != nil {
		return SigningKey{}, err
	}
	return key, nil
}

func (m *KeyManager) ActiveSigner(ctx context.Context, tenantID string) (vc.Signer, Delegation, error) {
	delegation, err := m.store.ActiveDelegation(tenantID, m.now())
	if err != nil {
		return nil, Delegation{}, err
	}
	key, err := m.store.SigningKey(tenantID, delegation.SigningKeyID)
	if err != nil {
		return nil, Delegation{}, err
	}
	signer, err := vc.NewGCPKMSEd25519Signer(ctx, key.KMSKeyVersion, m.kms, true)
	return signer, delegation, err
}
