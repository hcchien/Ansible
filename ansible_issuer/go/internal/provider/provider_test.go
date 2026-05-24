package provider_test

import (
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestMemoryStateProviderRejectsReplayedCallbackState(t *testing.T) {
	p := provider.NewMemoryStateProvider(provider.MemoryStateConfig{
		TTL: time.Minute,
	})

	if err := p.StartAuth("offer-1", "state-1"); err != nil {
		t.Fatalf("start auth: %v", err)
	}

	first := p.HandleCallback(map[string]string{
		"state":            "state-1",
		"assertion":        "signed",
		"provider_subject": "subject-1",
	})
	if !first.Verified {
		t.Fatalf("expected first callback verified, got %+v", first)
	}

	replay := p.HandleCallback(map[string]string{
		"state":            "state-1",
		"assertion":        "signed",
		"provider_subject": "subject-1",
	})
	if replay.Error != provider.ErrCallbackReplay {
		t.Fatalf("expected callback replay, got %+v", replay)
	}
}

func TestMemoryStateProviderRejectsStateMismatch(t *testing.T) {
	p := provider.NewMemoryStateProvider(provider.MemoryStateConfig{
		TTL: time.Minute,
	})

	if err := p.StartAuth("offer-1", "state-1"); err != nil {
		t.Fatalf("start auth: %v", err)
	}

	result := p.HandleCallback(map[string]string{
		"state":            "state-2",
		"assertion":        "signed",
		"provider_subject": "subject-1",
	})
	if result.Error != provider.ErrStateMismatch {
		t.Fatalf("expected state mismatch, got %+v", result)
	}
}

func TestMemoryStateProviderRejectsExpiredSession(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	p := provider.NewMemoryStateProvider(provider.MemoryStateConfig{
		TTL: time.Minute,
		Now: func() time.Time {
			return now
		},
	})

	if err := p.StartAuth("offer-1", "state-1"); err != nil {
		t.Fatalf("start auth: %v", err)
	}

	now = now.Add(2 * time.Minute)
	result := p.HandleCallback(map[string]string{
		"state":            "state-1",
		"assertion":        "signed",
		"provider_subject": "subject-1",
	})
	if result.Error != provider.ErrExpiredSession {
		t.Fatalf("expected expired session, got %+v", result)
	}
}

func TestMemoryStateProviderRejectsMissingProviderSubject(t *testing.T) {
	p := provider.NewMemoryStateProvider(provider.MemoryStateConfig{
		TTL: time.Minute,
	})

	if err := p.StartAuth("offer-1", "state-1"); err != nil {
		t.Fatalf("start auth: %v", err)
	}

	result := p.HandleCallback(map[string]string{
		"state":     "state-1",
		"assertion": "signed",
	})
	if result.Error != provider.ErrMissingProviderProof {
		t.Fatalf("expected missing provider proof, got %+v", result)
	}
}

func TestMemoryStateProviderRejectsMissingProviderProof(t *testing.T) {
	p := provider.NewMemoryStateProvider(provider.MemoryStateConfig{
		TTL: time.Minute,
	})

	if err := p.StartAuth("offer-1", "state-1"); err != nil {
		t.Fatalf("start auth: %v", err)
	}

	result := p.HandleCallback(map[string]string{
		"state": "state-1",
	})
	if result.Error != provider.ErrMissingProviderProof {
		t.Fatalf("expected missing provider proof, got %+v", result)
	}
}
