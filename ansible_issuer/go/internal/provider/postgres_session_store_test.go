package provider_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/pgstore"
	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestPostgresSessionStore(t *testing.T) {
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
	for _, tbl := range []string{"provider_auth_sessions", "provider_verified_sessions", "provider_replay_ids"} {
		if _, err := pool.Exec(ctx, "DELETE FROM "+tbl); err != nil {
			t.Fatalf("truncate %s: %v", tbl, err)
		}
	}

	now := time.Date(2026, 6, 5, 12, 0, 0, 0, time.UTC)
	clock := func() time.Time { return now }
	s := provider.NewPostgresSessionStore(pool, "tw", clock)
	exp := now.Add(5 * time.Minute)

	// Auth session: create -> get-by-offer -> consume.
	if err := s.CreateAuthSession(provider.AuthSession{
		OfferID: "o1", DID: "did:1", State: "st1", Email: "e", SubjectCommitment: "c1", ExpiresAt: exp,
	}); err != nil {
		t.Fatalf("create: %v", err)
	}
	if got, err := s.GetAuthSessionByOfferID("o1"); err != nil || got.State != "st1" {
		t.Fatalf("get by offer: %v %+v", err, got)
	}
	cons, err := s.ConsumeAuthState("st1", "")
	if err != nil || !cons.Consumed || cons.OfferID != "o1" {
		t.Fatalf("consume: %v %+v", err, cons)
	}
	// Replay: a second consume is rejected.
	if _, err := s.ConsumeAuthState("st1", ""); err != provider.ErrReplay {
		t.Fatalf("want replay, got %v", err)
	}
	if _, err := s.ConsumeAuthState("missing", ""); err != provider.ErrStateNotFound {
		t.Fatalf("want state_not_found, got %v", err)
	}

	// Verified session: store -> get -> consume -> gone.
	if err := s.StoreVerifiedSession(provider.VerifiedSession{
		OfferID: "o2", DID: "did:1", SubjectCommitment: "c2", VerifiedAt: now, ExpiresAt: exp,
	}); err != nil {
		t.Fatalf("store verified: %v", err)
	}
	if v, err := s.GetVerifiedSession("o2"); err != nil || v.SubjectCommitment != "c2" {
		t.Fatalf("get verified: %v %+v", err, v)
	}
	if cv, err := s.ConsumeVerifiedSession("o2"); err != nil || !cv.Consumed {
		t.Fatalf("consume verified: %v %+v", err, cv)
	}
	if _, err := s.GetVerifiedSession("o2"); err != provider.ErrVerifiedNotFound {
		t.Fatalf("want verified_not_found after consume, got %v", err)
	}

	// Namespace isolation.
	other := provider.NewPostgresSessionStore(pool, "mobilemoica", clock)
	if _, err := other.GetAuthSessionByOfferID("o1"); err != provider.ErrStateNotFound {
		t.Fatalf("namespace leak: %v", err)
	}

	// Cleanup removes sessions expired beyond retention.
	if err := s.CreateAuthSession(provider.AuthSession{
		OfferID: "o3", DID: "d", State: "st3", ExpiresAt: now.Add(-2 * time.Hour),
	}); err != nil {
		t.Fatalf("create o3: %v", err)
	}
	if err := s.CleanupExpired(time.Hour); err != nil {
		t.Fatalf("cleanup: %v", err)
	}
	if _, err := s.GetAuthSessionByOfferID("o3"); err != provider.ErrStateNotFound {
		t.Fatalf("expected o3 cleaned up, got %v", err)
	}
}
