package vc

import (
	"context"
	"os"
	"testing"

	"github.com/trisaura/ansible_issuer/internal/pgstore"
)

func TestPostgresStoreDuplicatePrevention(t *testing.T) {
	url := os.Getenv("ISSUER_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("ISSUER_TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	pool, err := pgstore.Connect(ctx, url)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer pool.Close()
	if err := pgstore.EnsureSchema(ctx, pool); err != nil {
		t.Fatalf("schema: %v", err)
	}
	if _, err := pool.Exec(ctx, "TRUNCATE personhood_bindings"); err != nil {
		t.Fatalf("truncate: %v", err)
	}

	s := NewPostgresStore(pool)

	if err := s.CheckDuplicate("comm-1"); err != nil {
		t.Fatalf("expected no duplicate, got %v", err)
	}

	if err := s.add(record{
		credentialID:   "c1",
		holderDID:      "did:key:1",
		commitment:     "comm-1",
		nationalIDHash: "comm-1",
		status:         StatusActive,
	}); err != nil {
		t.Fatalf("add c1: %v", err)
	}

	if err := s.CheckDuplicate("comm-1"); err != ErrDuplicateActiveCredential {
		t.Fatalf("expected duplicate, got %v", err)
	}

	// A concurrent second active binding for the same commitment is rejected by
	// the unique index at insert time.
	if err := s.add(record{
		credentialID:   "c2",
		holderDID:      "did:key:2",
		commitment:     "comm-1",
		nationalIDHash: "comm-1",
		status:         StatusActive,
	}); err != ErrDuplicateActiveCredential {
		t.Fatalf("expected duplicate on add, got %v", err)
	}

	// Passport/national-id personhood binding dedup.
	if err := s.CheckDuplicatePersonhoodBinding("nat-1", "pass-1"); err != nil {
		t.Fatalf("expected no binding dup, got %v", err)
	}
	if err := s.add(record{
		credentialID:       "c3",
		holderDID:          "did:key:3",
		nationalIDHash:     "nat-1",
		passportNumberHash: "pass-1",
		status:             StatusActive,
	}); err != nil {
		t.Fatalf("add c3: %v", err)
	}
	if err := s.CheckDuplicatePersonhoodBinding("nat-1", ""); err != ErrDuplicatePersonhoodBinding {
		t.Fatalf("expected binding dup by national id, got %v", err)
	}
	if err := s.CheckDuplicatePersonhoodBinding("", "pass-1"); err != ErrDuplicatePersonhoodBinding {
		t.Fatalf("expected binding dup by passport, got %v", err)
	}

	if st, ok := s.Status("c1"); !ok || st != StatusActive {
		t.Fatalf("status c1 = %v, %v", st, ok)
	}
	if b, ok := s.PersonhoodBindingByNationalIDHash("nat-1"); !ok || b.CredentialID != "c3" {
		t.Fatalf("binding lookup = %+v, %v", b, ok)
	}
}
