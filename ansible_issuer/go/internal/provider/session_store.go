package provider

import (
	"errors"
	"time"
)

var (
	ErrReplay              = errors.New("provider replay")
	ErrStateNotFound       = errors.New("provider state not found")
	ErrExpiredSessionState = errors.New("provider session expired")
	ErrVerifiedNotFound    = errors.New("verified session not found")
)

type AuthSession struct {
	OfferID   string    `json:"offer_id"`
	DID       string    `json:"did"`
	Email     string    `json:"email"`
	State     string    `json:"state"`
	ExpiresAt time.Time `json:"expires_at"`
	Consumed  bool      `json:"consumed"`
}

type VerifiedSession struct {
	OfferID           string    `json:"offer_id"`
	DID               string    `json:"did"`
	Email             string    `json:"email"`
	SubjectCommitment string    `json:"subject_commitment"`
	VerifiedAt        time.Time `json:"verified_at"`
	ExpiresAt         time.Time `json:"expires_at"`
	Consumed          bool      `json:"consumed"`
}

type SessionStore interface {
	CreateAuthSession(AuthSession) error
	ConsumeAuthState(state, replayID string) (AuthSession, error)
	MarkReplayIDConsumed(replayID string, expiresAt time.Time) error
	StoreVerifiedSession(VerifiedSession) error
	GetVerifiedSession(offerID string) (VerifiedSession, error)
	ConsumeVerifiedSession(offerID string) (VerifiedSession, error)
	CleanupExpired(retention time.Duration) error
}
