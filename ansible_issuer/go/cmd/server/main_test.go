package main

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
)

func TestBuildTWProviderConfigDefaultsMockModeToContractAdapter(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))

	config, err := buildTWProviderConfigFromEnv(true, func() time.Time {
		return time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	})
	if err != nil {
		t.Fatalf("build mock config: %v", err)
	}
	if config.BaseAuthURL != "https://provider.example/authorize" {
		t.Fatalf("unexpected auth URL: %s", config.BaseAuthURL)
	}
	if config.Verifier == nil {
		t.Fatal("expected verifier")
	}
}

func TestBuildTWProviderConfigRequiresAdapterModeOutsideMockMode(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))
	t.Setenv("TW_PROVIDER_AUTH_URL", "https://provider.example/authorize")
	t.Setenv("TW_PROVIDER_SHARED_SECRET", "provider-secret")
	t.Setenv("TW_PROVIDER_AUDIENCE", "trisaura-issuer")

	_, err := buildTWProviderConfigFromEnv(false, time.Now)
	if !errors.Is(err, errTWProviderConfigMissing) {
		t.Fatalf("expected missing config error, got %v", err)
	}
}

func TestBuildTWProviderConfigBuildsExplicitContractAdapter(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))
	t.Setenv("TW_PROVIDER_AUTH_URL", "https://provider.example/authorize")
	t.Setenv("TW_PROVIDER_ADAPTER_MODE", "contract")
	t.Setenv("TW_PROVIDER_SHARED_SECRET", "provider-secret")
	t.Setenv("TW_PROVIDER_AUDIENCE", "trisaura-issuer")

	config, err := buildTWProviderConfigFromEnv(false, func() time.Time {
		return time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	})
	if err != nil {
		t.Fatalf("build contract config: %v", err)
	}
	if config.Verifier == nil {
		t.Fatal("expected verifier")
	}
	if config.Retention != 24*time.Hour {
		t.Fatalf("unexpected default retention: %s", config.Retention)
	}
}

func TestBuildTWProviderConfigUsesRetentionOverride(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))
	t.Setenv("TW_PROVIDER_AUTH_URL", "https://provider.example/authorize")
	t.Setenv("TW_PROVIDER_ADAPTER_MODE", "contract")
	t.Setenv("TW_PROVIDER_SHARED_SECRET", "provider-secret")
	t.Setenv("TW_PROVIDER_AUDIENCE", "trisaura-issuer")
	t.Setenv("TW_PROVIDER_RETENTION_SECONDS", "3600")

	config, err := buildTWProviderConfigFromEnv(false, time.Now)
	if err != nil {
		t.Fatalf("build contract config: %v", err)
	}
	if config.Retention != time.Hour {
		t.Fatalf("unexpected retention override: %s", config.Retention)
	}
}

func TestBuildTWProviderConfigCleansExpiredSessionsAtStartup(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	path := filepath.Join(t.TempDir(), "sessions.json")
	store, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	if err := store.MarkReplayIDConsumed("old-replay", now.Add(-2*time.Hour)); err != nil {
		t.Fatalf("mark old replay: %v", err)
	}

	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", path)
	t.Setenv("TW_PROVIDER_AUTH_URL", "https://provider.example/authorize")
	t.Setenv("TW_PROVIDER_ADAPTER_MODE", "contract")
	t.Setenv("TW_PROVIDER_SHARED_SECRET", "provider-secret")
	t.Setenv("TW_PROVIDER_AUDIENCE", "trisaura-issuer")
	t.Setenv("TW_PROVIDER_RETENTION_SECONDS", "3600")

	if _, err := buildTWProviderConfigFromEnv(false, func() time.Time { return now }); err != nil {
		t.Fatalf("build config: %v", err)
	}

	reopened, err := provider.NewFileSessionStore(path, func() time.Time { return now })
	if err != nil {
		t.Fatalf("reopen store: %v", err)
	}
	if err := reopened.MarkReplayIDConsumed("old-replay", now.Add(time.Hour)); err != nil {
		t.Fatalf("expected startup cleanup to remove old replay, got %v", err)
	}
}

func TestBuildTWProviderConfigProductionModeFailsClosed(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))
	t.Setenv("TW_PROVIDER_AUTH_URL", "https://provider.example/authorize")
	t.Setenv("TW_PROVIDER_ADAPTER_MODE", "production")
	t.Setenv("TW_PROVIDER_PRODUCTION_TRUST_ANCHORS", "tw-provider-root-ca")
	t.Setenv("TW_PROVIDER_PRODUCTION_AUDIENCE", "trisaura-issuer")

	_, err := buildTWProviderConfigFromEnv(false, time.Now)
	if !errors.Is(err, provider.ErrProductionAdapterUnavailable) {
		t.Fatalf("expected production unavailable error, got %v", err)
	}
}
