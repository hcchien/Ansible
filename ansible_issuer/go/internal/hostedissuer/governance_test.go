package hostedissuer

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"testing"
	"time"
)

func TestGovernanceRequiresHardwareRootSignature(t *testing.T) {
	now := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	store := NewMemoryStore()
	tenant := Tenant{ID: "ntp", OrganizationDID: "did:web:ntp.example", ServiceSlug: "ntp", Threshold: 1, AdministratorCount: 2}
	if err := store.CreateTenant(tenant); err != nil {
		t.Fatal(err)
	}
	private, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	publicHex := hex.EncodeToString(elliptic.Marshal(elliptic.P256(), private.X, private.Y))
	admin := Administrator{DID: "did:plc:admin", Role: "owner", State: "active", SigningAlgorithm: "p256-sha256", PublicKeyHex: publicHex, Custody: "hardware"}
	if err := store.PutAdministrator("ntp", admin); err != nil {
		t.Fatal(err)
	}
	payload := []byte(fmt.Sprintf(`{"type":"IssuerKeyDelegation","version":1,"issuer":"did:web:ntp.example","delegate_key":"did:key:z6Mk","service":"https://issuer.example/tenants/ntp","credential_types":["PoliticalPartyMembershipCredential"],"not_before":"%s","expires_at":"%s","approval_policy":{"threshold":1,"administrators":1},"sequence":1}`, now.Add(-time.Minute).Format(time.RFC3339), now.Add(time.Hour).Format(time.RFC3339)))
	governance := NewGovernance(store, func() time.Time { return now })
	delegation, err := governance.ValidateDelegation(tenant, payload)
	if err != nil {
		t.Fatal(err)
	}
	delegation.ID = "d1"
	if err := store.ProposeDelegation("ntp", delegation); err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(payload)
	signature, err := ecdsa.SignASN1(rand.Reader, private, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	if err := governance.ApproveDelegation("ntp", "d1", admin.DID, payload, signature); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateDelegation("ntp", "d1", now); err != nil {
		t.Fatal(err)
	}

	admin.Custody = "reduced_trust"
	admin.DID = "did:plc:desktop"
	if err := store.PutAdministrator("ntp", admin); err != nil {
		t.Fatal(err)
	}
	if err := governance.ApproveDelegation("ntp", "d1", admin.DID, payload, signature); err == nil {
		t.Fatal("expected reduced-trust root administrator rejection")
	}
}

func TestDelegationStrictSchemaRejectsUnknownSecurityField(t *testing.T) {
	tenant := Tenant{ID: "t", OrganizationDID: "did:web:t", Threshold: 1}
	governance := NewGovernance(NewMemoryStore(), nil)
	payload := []byte(`{"type":"IssuerKeyDelegation","version":1,"issuer":"did:web:t","delegate_key":"did:key:x","service":"https://issuer.example/t","credential_types":["MembershipCredential"],"not_before":"2026-01-01T00:00:00Z","expires_at":"2027-01-01T00:00:00Z","approval_policy":{"threshold":1,"administrators":1},"sequence":1,"allow_all":true}`)
	if _, err := governance.ValidateDelegation(tenant, payload); err == nil {
		t.Fatalf("expected unknown field rejection, got %v", err)
	}
}
