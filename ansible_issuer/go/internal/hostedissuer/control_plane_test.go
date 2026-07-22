package hostedissuer

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"testing"
	"time"
)

func TestBootstrapRequiresHardwareSignatureAndCreatesOwnerAtomically(t *testing.T) {
	now := time.Now().UTC()
	private, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	request := BootstrapRequest{
		Type: "HostedIssuerBootstrap", Version: 1, OrganizationDID: "did:web:party.example",
		ServiceSlug: "party-example", ApprovalThreshold: 2, AdministratorCount: 3,
		OwnerDID: "did:plc:owner", OwnerPublicKeyHex: hex.EncodeToString(elliptic.Marshal(elliptic.P256(), private.X, private.Y)),
		OwnerKeyAlgorithm: "p256-sha256", OwnerCustody: "hardware", IssuedAt: now,
	}
	canonical, err := canonicalBootstrap(request)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(canonical)
	signature, err := ecdsa.SignASN1(rand.Reader, private, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	request.SignatureHex = hex.EncodeToString(signature)
	store := NewMemoryStore()
	control := NewControlPlane(store, func() time.Time { return now })
	tenant, err := control.Bootstrap(request)
	if err != nil {
		t.Fatal(err)
	}
	admins, err := store.Administrators(tenant.ID)
	if err != nil || len(admins) != 1 || admins[0].Role != "owner" || admins[0].State != "active" {
		t.Fatalf("unexpected bootstrap owner: %#v, %v", admins, err)
	}

	tampered := request
	tampered.ApprovalThreshold = 1
	if _, err := control.Bootstrap(tampered); err == nil {
		t.Fatal("tampered bootstrap must fail signature verification")
	}
}
