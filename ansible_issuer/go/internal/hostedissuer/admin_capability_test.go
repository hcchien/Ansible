package hostedissuer

import (
	"errors"
	"testing"
	"time"
)

func TestAdminCapabilityIsTenantAudienceScopeAndExpiryBound(t *testing.T) {
	now := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	store := NewMemoryAdminCapabilityStore()
	service := NewAdminCapabilityService(store, func() time.Time { return now })
	token, capability, err := service.Issue("tenant-a", "did:plc:admin", []string{"issuer_admin:keys"}, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if token == capability.TokenHash || len(capability.TokenHash) != 64 {
		t.Fatal("store must only receive a token hash")
	}
	if _, err := service.Authorize(token, "tenant-b", "issuer_admin:keys"); !errors.Is(err, ErrCapabilityInvalid) {
		t.Fatalf("expected cross-tenant denial, got %v", err)
	}
	if _, err := service.Authorize(token, "tenant-a", "issuer_admin:audit"); !errors.Is(err, ErrCapabilityScope) {
		t.Fatalf("expected scope denial, got %v", err)
	}
	if _, err := service.Authorize("sync_v1_not_an_issuer_token", "tenant-a", "issuer_admin:keys"); !errors.Is(err, ErrCapabilityInvalid) {
		t.Fatalf("expected relay-token denial, got %v", err)
	}
	now = now.Add(2 * time.Minute)
	if _, err := service.Authorize(token, "tenant-a", "issuer_admin:keys"); !errors.Is(err, ErrCapabilityInvalid) {
		t.Fatalf("expected expiry denial, got %v", err)
	}
}
