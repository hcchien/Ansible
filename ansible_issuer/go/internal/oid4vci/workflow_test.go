package oid4vci

import (
	"errors"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/hostedissuer"
)

func TestCredentialOfferRequiresThresholdApprovedSingleUseRequest(t *testing.T) {
	now := time.Date(2026, 7, 22, 12, 0, 0, 0, time.UTC)
	store := hostedissuer.NewMemoryStore()
	tenant := hostedissuer.Tenant{
		ID: "party", OrganizationDID: "did:web:party.example", ServiceSlug: "party",
		Status: hostedissuer.TenantActive, Threshold: 2, AdministratorCount: 2,
		PolicyVersion: 1, CreatedAt: now,
	}
	if err := store.CreateTenant(tenant); err != nil {
		t.Fatal(err)
	}
	for _, did := range []string{"did:example:admin-1", "did:example:admin-2"} {
		if err := store.PutAdministrator("party", hostedissuer.Administrator{
			DID: did, Role: "administrator", State: "active",
		}); err != nil {
			t.Fatal(err)
		}
	}
	issuer := NewIssuer(
		NewStateService(NewMemoryStateStore(), func() time.Time { return now }),
		store,
		nil,
		"https://issuer.example",
		func() time.Time { return now },
	)
	if _, err := issuer.PutMembershipTemplate("party", 1, 90, true); err != nil {
		t.Fatal(err)
	}
	request, err := issuer.CreateBoardIssuanceRequest(
		"party",
		"did:jwk:eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6IngiLCJ5IjoieSJ9",
		"member",
		"board-party-members",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := issuer.CreateOfferForApprovedRequest("party", request.ID); err == nil {
		t.Fatal("pending request must not create an offer")
	}
	first, err := issuer.DecideIssuanceRequest(
		"party", request.ID, "did:example:admin-1", "approve", "decision-hash-1",
	)
	if err != nil || first.State != "pending" {
		t.Fatalf("first approval must remain pending: request=%+v err=%v", first, err)
	}
	if _, err := issuer.CreateOfferForApprovedRequest("party", request.ID); err == nil {
		t.Fatal("one of two approvals must not create an offer")
	}
	approved, err := issuer.DecideIssuanceRequest(
		"party", request.ID, "did:example:admin-2", "approve", "decision-hash-2",
	)
	if err != nil || approved.State != "approved" {
		t.Fatalf("threshold approval must approve: request=%+v err=%v", approved, err)
	}
	offer, err := issuer.CreateOfferForApprovedRequest("party", request.ID)
	if err != nil || offer["credential_issuer"] != "https://issuer.example/tenants/party" {
		t.Fatalf("approved request must create offer: offer=%+v err=%v", offer, err)
	}
	if _, err := issuer.CreateOfferForApprovedRequest("party", request.ID); !errors.Is(err, hostedissuer.ErrDelegationInvalid) {
		t.Fatalf("issuance request must be single-use, got %v", err)
	}
}

func TestIssuanceDenialIsTerminal(t *testing.T) {
	now := time.Date(2026, 7, 22, 12, 0, 0, 0, time.UTC)
	store := hostedissuer.NewMemoryStore()
	if err := store.CreateTenant(hostedissuer.Tenant{
		ID: "party", OrganizationDID: "did:web:party.example", ServiceSlug: "party",
		Threshold: 1, AdministratorCount: 1,
	}); err != nil {
		t.Fatal(err)
	}
	_ = store.PutAdministrator("party", hostedissuer.Administrator{DID: "did:example:admin", State: "active"})
	issuer := NewIssuer(NewStateService(NewMemoryStateStore(), func() time.Time { return now }), store, nil, "https://issuer.example", func() time.Time { return now })
	_, _ = issuer.PutMembershipTemplate("party", 1, 30, true)
	request, _ := issuer.CreateBoardIssuanceRequest("party", "did:jwk:holder", "member", "board-party-members")
	denied, err := issuer.DecideIssuanceRequest("party", request.ID, "did:example:admin", "deny", "deny-hash")
	if err != nil || denied.State != "denied" {
		t.Fatalf("denial must be terminal: request=%+v err=%v", denied, err)
	}
	if _, err := issuer.DecideIssuanceRequest("party", request.ID, "did:example:admin", "approve", "approve-hash"); err == nil {
		t.Fatal("denied request must not be revived")
	}
}
