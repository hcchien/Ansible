package provider

import (
	"errors"
	"sync"
	"time"
)

const (
	ErrCallbackReplay       = "callback_replay"
	ErrStateMismatch        = "state_mismatch"
	ErrExpiredSession       = "expired_session"
	ErrMissingProviderProof = "missing_provider_proof"
)

// MemoryStateConfig controls the in-memory provider adapter used for tests and
// local readiness checks before a production TW FidO/MOICA adapter is wired.
type MemoryStateConfig struct {
	TTL time.Duration
	Now func() time.Time
}

// CallbackResult is the normalized output of a provider callback.
type CallbackResult struct {
	Verified        bool
	OfferID         string
	ProviderSubject string
	ReplayID        string
	Error           string
}

type authSession struct {
	offerID   string
	expiresAt time.Time
	consumed  bool
}

// MemoryStateProvider tracks issued auth state and consumed callback replay IDs.
type MemoryStateProvider struct {
	mu        sync.Mutex
	ttl       time.Duration
	now       func() time.Time
	sessions  map[string]authSession
	replayIDs map[string]struct{}
}

// NewMemoryStateProvider creates an in-memory adapter for contract tests.
func NewMemoryStateProvider(config MemoryStateConfig) *MemoryStateProvider {
	ttl := config.TTL
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	now := config.Now
	if now == nil {
		now = time.Now
	}
	return &MemoryStateProvider{
		ttl:       ttl,
		now:       now,
		sessions:  make(map[string]authSession),
		replayIDs: make(map[string]struct{}),
	}
}

// StartAuth records an outbound provider session keyed by callback state.
func (p *MemoryStateProvider) StartAuth(offerID, state string) error {
	if offerID == "" || state == "" {
		return errors.New("missing auth session field")
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	p.sessions[state] = authSession{
		offerID:   offerID,
		expiresAt: p.now().Add(p.ttl),
	}
	return nil
}

// HandleCallback validates callback state, proof presence, replay, and expiry.
func (p *MemoryStateProvider) HandleCallback(callback map[string]string) CallbackResult {
	state := callback["state"]
	assertion := callback["assertion"]
	replayID := callback["replay_id"]
	if replayID == "" {
		replayID = state
	}

	p.mu.Lock()
	defer p.mu.Unlock()

	session, ok := p.sessions[state]
	if !ok {
		return CallbackResult{ReplayID: replayID, Error: ErrStateMismatch}
	}
	if p.now().After(session.expiresAt) {
		delete(p.sessions, state)
		return CallbackResult{OfferID: session.offerID, ReplayID: replayID, Error: ErrExpiredSession}
	}
	if assertion == "" {
		return CallbackResult{OfferID: session.offerID, ReplayID: replayID, Error: ErrMissingProviderProof}
	}
	if session.consumed {
		return CallbackResult{OfferID: session.offerID, ReplayID: replayID, Error: ErrCallbackReplay}
	}
	if _, seen := p.replayIDs[replayID]; seen {
		session.consumed = true
		p.sessions[state] = session
		return CallbackResult{OfferID: session.offerID, ReplayID: replayID, Error: ErrCallbackReplay}
	}

	session.consumed = true
	p.sessions[state] = session
	p.replayIDs[replayID] = struct{}{}

	subject := callback["provider_subject"]
	if subject == "" {
		subject = "assertion:" + assertion
	}
	return CallbackResult{
		Verified:        true,
		OfferID:         session.offerID,
		ProviderSubject: subject,
		ReplayID:        replayID,
	}
}
