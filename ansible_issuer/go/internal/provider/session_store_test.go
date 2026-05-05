package provider_test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestFileSessionStoreConsumesStateOnce(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	session := provider.AuthSession{
		OfferID:   "offer-1",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "state-1",
		ExpiresAt: now.Add(time.Minute),
	}
	if err := store.CreateAuthSession(session); err != nil {
		t.Fatalf("create session: %v", err)
	}

	first, err := store.ConsumeAuthState("state-1", "replay-1")
	if err != nil {
		t.Fatalf("consume first: %v", err)
	}
	if first.OfferID != "offer-1" {
		t.Fatalf("unexpected offer: %+v", first)
	}

	_, err = store.ConsumeAuthState("state-1", "replay-1")
	if err != provider.ErrReplay {
		t.Fatalf("expected replay, got %v", err)
	}
}

func TestFileSessionStoreRejectsExpiredState(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	err = store.CreateAuthSession(provider.AuthSession{
		OfferID:   "offer-1",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "state-1",
		ExpiresAt: now.Add(-time.Second),
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	_, err = store.ConsumeAuthState("state-1", "replay-1")
	if err != provider.ErrExpiredSessionState {
		t.Fatalf("expected expired session, got %v", err)
	}
}

func TestFileSessionStorePersistsReplayAcrossRestart(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "provider_sessions.json")
	store, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	if err := store.MarkReplayIDConsumed("replay-1", now.Add(time.Hour)); err != nil {
		t.Fatalf("mark replay: %v", err)
	}

	reopened, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}
	if err := reopened.MarkReplayIDConsumed("replay-1", now.Add(time.Hour)); err != provider.ErrReplay {
		t.Fatalf("expected persisted replay rejection, got %v", err)
	}
}

func TestFileSessionStoreStoresVerifiedCommitment(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store, err := provider.NewFileSessionStore(filepath.Join(t.TempDir(), "provider_sessions.json"), func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	verified := provider.VerifiedSession{
		OfferID:           "offer-1",
		DID:               "did:plc:abcdefghijklmnop",
		Email:             "alice@example.com",
		SubjectCommitment: "commitment-1",
		VerifiedAt:        now,
		ExpiresAt:         now.Add(5 * time.Minute),
	}
	if err := store.StoreVerifiedSession(verified); err != nil {
		t.Fatalf("store verified session: %v", err)
	}

	got, err := store.GetVerifiedSession("offer-1")
	if err != nil {
		t.Fatalf("get verified session: %v", err)
	}
	if got.SubjectCommitment != "commitment-1" {
		t.Fatalf("unexpected verified session: %+v", got)
	}
}

func TestFileSessionStoreCleanupExpiredRemovesOldSessionsAndReplays(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "provider_sessions.json")
	store, err := provider.NewFileSessionStore(path, func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	if err := store.CreateAuthSession(provider.AuthSession{
		OfferID:   "old-auth",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "old-state",
		ExpiresAt: now.Add(-2 * time.Hour),
	}); err != nil {
		t.Fatalf("create old auth: %v", err)
	}
	if err := store.CreateAuthSession(provider.AuthSession{
		OfferID:   "recent-auth",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "recent-state",
		ExpiresAt: now.Add(-30 * time.Minute),
	}); err != nil {
		t.Fatalf("create recent auth: %v", err)
	}
	if err := store.StoreVerifiedSession(provider.VerifiedSession{
		OfferID:           "old-verified",
		DID:               "did:plc:abcdefghijklmnop",
		Email:             "alice@example.com",
		SubjectCommitment: "commitment-old",
		VerifiedAt:        now.Add(-3 * time.Hour),
		ExpiresAt:         now.Add(-2 * time.Hour),
	}); err != nil {
		t.Fatalf("store old verified: %v", err)
	}
	if err := store.MarkReplayIDConsumed("old-replay", now.Add(-2*time.Hour)); err != nil {
		t.Fatalf("mark old replay: %v", err)
	}
	if err := store.MarkReplayIDConsumed("recent-replay", now.Add(30*time.Minute)); err != nil {
		t.Fatalf("mark recent replay: %v", err)
	}

	if err := store.CleanupExpired(time.Hour); err != nil {
		t.Fatalf("cleanup: %v", err)
	}

	reopened, err := provider.NewFileSessionStore(path, func() time.Time {
		return now
	})
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}

	if _, err := reopened.GetAuthSessionByOfferID("old-auth"); err != provider.ErrStateNotFound {
		t.Fatalf("expected old auth removed, got %v", err)
	}
	if err := reopened.MarkReplayIDConsumed("old-replay", now.Add(time.Hour)); err != nil {
		t.Fatalf("expected old replay removed, got %v", err)
	}
	if err := reopened.MarkReplayIDConsumed("recent-replay", now.Add(time.Hour)); err != provider.ErrReplay {
		t.Fatalf("expected recent replay retained, got %v", err)
	}
}

func TestMemorySessionStoreCleanupExpiredRemovesOldSessionsAndReplays(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	store := provider.NewMemorySessionStore(func() time.Time { return now })

	if err := store.CreateAuthSession(provider.AuthSession{
		OfferID:   "old-auth",
		DID:       "did:plc:abcdefghijklmnop",
		Email:     "alice@example.com",
		State:     "old-state",
		ExpiresAt: now.Add(-2 * time.Hour),
	}); err != nil {
		t.Fatalf("create old auth: %v", err)
	}
	if err := store.StoreVerifiedSession(provider.VerifiedSession{
		OfferID:           "old-verified",
		DID:               "did:plc:abcdefghijklmnop",
		Email:             "alice@example.com",
		SubjectCommitment: "commitment-old",
		VerifiedAt:        now.Add(-3 * time.Hour),
		ExpiresAt:         now.Add(-2 * time.Hour),
	}); err != nil {
		t.Fatalf("store old verified: %v", err)
	}
	if err := store.MarkReplayIDConsumed("old-replay", now.Add(-2*time.Hour)); err != nil {
		t.Fatalf("mark old replay: %v", err)
	}

	if err := store.CleanupExpired(time.Hour); err != nil {
		t.Fatalf("cleanup: %v", err)
	}

	if _, err := store.GetAuthSessionByOfferID("old-auth"); err != provider.ErrStateNotFound {
		t.Fatalf("expected old auth removed, got %v", err)
	}
	if err := store.MarkReplayIDConsumed("old-replay", now.Add(time.Hour)); err != nil {
		t.Fatalf("expected old replay removed, got %v", err)
	}
}
