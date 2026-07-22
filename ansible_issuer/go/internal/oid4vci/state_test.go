package oid4vci

import (
	"errors"
	"testing"
	"time"
)

func TestPreAuthorizedCodeNonceAndAccessAreSingleUse(t *testing.T) {
	now := time.Now().UTC()
	service := NewStateService(NewMemoryStateStore(), func() time.Time { return now })
	code, _, err := service.CreatePreAuthorizedGrant("tenant-a", "membership-v1", "pairwise-hash", "member")
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := service.ExchangePreAuthorizedCode(code, "tenant-b"); !errors.Is(err, ErrInvalidGrant) {
		t.Fatalf("cross-tenant exchange accepted: %v", err)
	}
	token, access, err := service.ExchangePreAuthorizedCode(code, "tenant-a")
	if err != nil || access.TenantID != "tenant-a" {
		t.Fatalf("exchange failed: %#v %v", access, err)
	}
	if access.MembershipClass != "member" {
		t.Fatalf("approved membership class was not bound to access: %#v", access)
	}
	if _, _, err := service.ExchangePreAuthorizedCode(code, "tenant-a"); !errors.Is(err, ErrInvalidGrant) {
		t.Fatalf("offer replay accepted: %v", err)
	}
	nonce, err := service.IssueNonce()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.AuthorizeCredential(token, nonce); err != nil {
		t.Fatal(err)
	}
	if _, err := service.AuthorizeCredential(token, nonce); !errors.Is(err, ErrInvalidNonce) {
		t.Fatalf("nonce replay accepted: %v", err)
	}
	if err := service.MarkCredentialIssued(token); err != nil {
		t.Fatal(err)
	}
	nonce2, _ := service.IssueNonce()
	if _, err := service.AuthorizeCredential(token, nonce2); err != nil {
		t.Fatalf("idempotent credential response retry was rejected: %v", err)
	}
}

func TestPreparedIssuanceStateIsStableAcrossRetries(t *testing.T) {
	now := time.Now().UTC()
	service := NewStateService(NewMemoryStateStore(), func() time.Time { return now })
	code, _, _ := service.CreatePreAuthorizedGrant("tenant-a", "membership-v1", "did:peer:holder", "moderator")
	token, _, _ := service.ExchangePreAuthorizedCode(code, "tenant-a")

	first, err := service.PrepareCredential(token, 42, now)
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.PrepareCredential(token, 99, now.Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if first.StatusIndex == nil || second.StatusIndex == nil || *first.StatusIndex != 42 || *second.StatusIndex != 42 {
		t.Fatalf("status index changed across retry: %#v %#v", first, second)
	}
	if first.IssuedAt == nil || second.IssuedAt == nil || !first.IssuedAt.Equal(*second.IssuedAt) {
		t.Fatalf("issued_at changed across retry: %#v %#v", first, second)
	}
}

func TestPreAuthorizedGrantRejectsWalletControlledMembershipClass(t *testing.T) {
	service := NewStateService(NewMemoryStateStore(), time.Now)
	for _, class := range []string{"", "owner", "administrator", "MODERATOR"} {
		if _, _, err := service.CreatePreAuthorizedGrant("tenant-a", "membership-v1", "did:peer:holder", class); !errors.Is(err, ErrInvalidGrant) {
			t.Fatalf("unexpected membership class %q accepted: %v", class, err)
		}
	}
}
