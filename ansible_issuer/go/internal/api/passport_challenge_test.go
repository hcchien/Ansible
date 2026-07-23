package api

import (
	"errors"
	"testing"
	"time"
)

func TestPassportChallengeIsDIDBoundAndSingleUse(t *testing.T) {
	now := time.Date(2026, 7, 23, 4, 0, 0, 0, time.UTC)
	store := NewMemoryPassportChallengeStore()
	challenge, nonce, err := newPassportChallenge("did:plc:abcdefghijklmnop", "https://issuer-dev.elix.cool", now)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.PutPassportChallenge(challenge); err != nil {
		t.Fatal(err)
	}
	if challenge.NonceHash == nonce || challenge.NonceHash == "" {
		t.Fatal("store retained plaintext nonce")
	}
	if err := store.ConsumePassportChallenge(challenge.ID, "did:plc:otheridentity", hashPassportNonce(nonce), now); !errors.Is(err, ErrInvalidPassportChallenge) {
		t.Fatalf("wrong DID accepted: %v", err)
	}
	if err := store.ConsumePassportChallenge(challenge.ID, challenge.DID, hashPassportNonce(nonce), now); err != nil {
		t.Fatal(err)
	}
	if err := store.ConsumePassportChallenge(challenge.ID, challenge.DID, hashPassportNonce(nonce), now); !errors.Is(err, ErrInvalidPassportChallenge) {
		t.Fatalf("replay accepted: %v", err)
	}
}

func TestPassportChallengeExpires(t *testing.T) {
	now := time.Date(2026, 7, 23, 4, 0, 0, 0, time.UTC)
	store := NewMemoryPassportChallengeStore()
	challenge, nonce, _ := newPassportChallenge("did:plc:abcdefghijklmnop", "https://issuer-dev.elix.cool", now)
	if got := challenge.ExpiresAt.Sub(now); got != 15*time.Minute {
		t.Fatalf("challenge TTL = %v, want 15m", got)
	}
	if err := store.PutPassportChallenge(challenge); err != nil {
		t.Fatal(err)
	}
	if err := store.ConsumePassportChallenge(challenge.ID, challenge.DID, hashPassportNonce(nonce), now.Add(passportChallengeTTL)); !errors.Is(err, ErrInvalidPassportChallenge) {
		t.Fatalf("expired challenge accepted: %v", err)
	}
}
