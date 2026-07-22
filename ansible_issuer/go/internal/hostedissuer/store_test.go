package hostedissuer

import (
	"errors"
	"testing"
	"time"
)

func TestTenantIsolationAndThresholdDelegation(t *testing.T) {
	store := NewMemoryStore()
	now := time.Now().UTC()
	for _, tenant := range []string{"a", "b"} {
		if err := store.CreateTenant(Tenant{ID: tenant, OrganizationDID: "did:web:" + tenant, ServiceSlug: tenant, Threshold: 2}); err != nil {
			t.Fatal(err)
		}
	}
	if err := store.PutAdministrator("a", Administrator{TenantID: "b", DID: "did:plc:x"}); !errors.Is(err, ErrTenantScope) {
		t.Fatalf("expected tenant-scope rejection, got %v", err)
	}
	for _, did := range []string{"did:plc:admin1", "did:plc:admin2"} {
		if err := store.PutAdministrator("a", Administrator{DID: did, Role: "owner", State: "active"}); err != nil {
			t.Fatal(err)
		}
	}
	if err := store.PutAdministrator("a", Administrator{DID: "did:plc:admin3", Role: "administrator", State: "active"}); !errors.Is(err, ErrThresholdNotMet) {
		t.Fatalf("administrator capacity must be enforced, got %v", err)
	}
	delegation := Delegation{ID: "d1", Sequence: 1, PayloadHash: "hash", NotBefore: now.Add(-time.Minute), ExpiresAt: now.Add(time.Hour)}
	if err := store.ProposeDelegation("a", delegation); err != nil {
		t.Fatal(err)
	}
	if err := store.ApproveDelegation("a", "d1", "did:plc:admin1", []byte("sig1")); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateDelegation("a", "d1", now); !errors.Is(err, ErrThresholdNotMet) {
		t.Fatalf("expected threshold failure, got %v", err)
	}
	if err := store.ApproveDelegation("a", "d1", "did:plc:admin2", []byte("sig2")); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateDelegation("a", "d1", now); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ActiveDelegation("b", now); !errors.Is(err, ErrNotFound) {
		t.Fatalf("tenant b must not observe tenant a delegation: %v", err)
	}
	if err := store.RevokeDelegation("a", "d1", now); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ActiveDelegation("a", now); !errors.Is(err, ErrNotFound) {
		t.Fatalf("revoked delegation must stop issuance immediately: %v", err)
	}
	tenant, err := store.Tenant("a")
	if err != nil || tenant.Status != TenantPaused {
		t.Fatalf("revoking the active delegation must pause tenant: tenant=%+v err=%v", tenant, err)
	}
	if err := store.ProposeDelegation("a", Delegation{ID: "replay", Sequence: 1, PayloadHash: "h2", ExpiresAt: now.Add(time.Hour)}); !errors.Is(err, ErrDelegationReplay) {
		t.Fatalf("expected replay rejection, got %v", err)
	}
}
