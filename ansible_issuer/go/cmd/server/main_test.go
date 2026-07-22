package main

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

func TestIsProdLikeEnvironment(t *testing.T) {
	cases := []struct {
		name      string
		kService  string
		issuerURL string
		want      bool
	}{
		{"cloud run marker set", "ansible-issuer", "http://localhost:4002", true},
		{"local http", "", "http://localhost:4002", false},
		{"loopback https", "", "https://127.0.0.1:4002", false},
		{"dotlocalhost https", "", "https://issuer.localhost", false},
		{"private range https", "", "https://10.0.0.5", false},
		{"public https url", "", "https://issuer.trisaura.example", true},
		{"empty issuer url", "", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("K_SERVICE", tc.kService)
			if got := isProdLikeEnvironment(tc.issuerURL); got != tc.want {
				t.Fatalf("isProdLikeEnvironment(%q) with K_SERVICE=%q = %v, want %v", tc.issuerURL, tc.kService, got, tc.want)
			}
		})
	}
}

func TestBuildTWProviderConfigDefaultsMockModeToContractAdapter(t *testing.T) {
	t.Setenv("TW_PROVIDER_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "sessions.json"))

	config, err := buildTWProviderConfigFromEnv(true, func() time.Time {
		return time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	}, nil)
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

	_, err := buildTWProviderConfigFromEnv(false, time.Now, nil)
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
	}, nil)
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

	config, err := buildTWProviderConfigFromEnv(false, time.Now, nil)
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

	if _, err := buildTWProviderConfigFromEnv(false, func() time.Time { return now }, nil); err != nil {
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

	_, err := buildTWProviderConfigFromEnv(false, time.Now, nil)
	if !errors.Is(err, provider.ErrProductionAdapterUnavailable) {
		t.Fatalf("expected production unavailable error, got %v", err)
	}
}

func TestBuildMobileMoicaRPConfigDisabledByDefault(t *testing.T) {
	config, enabled, err := buildMobileMoicaRPConfigFromEnv(false, time.Now, nil)
	if err != nil {
		t.Fatalf("disabled config should not fail: %v", err)
	}
	if enabled {
		t.Fatal("expected MobileMoica RP disabled by default")
	}
	if config.Enabled {
		t.Fatalf("disabled config must not enable handler: %+v", config)
	}
}

func TestBuildCredentialStoreRequiresDurablePathOutsideMockMode(t *testing.T) {
	_, err := buildCredentialStoreFromEnv(false, nil)
	if !errors.Is(err, errPersonhoodBindingStoreConfigMissing) {
		t.Fatalf("expected missing durable binding store path error, got %v", err)
	}
}

func TestBuildCredentialStoreBuildsFileStoreWhenConfigured(t *testing.T) {
	t.Setenv("PERSONHOOD_BINDING_STORE_PATH", filepath.Join(t.TempDir(), "personhood-bindings.json"))

	store, err := buildCredentialStoreFromEnv(false, nil)
	if err != nil {
		t.Fatalf("build credential store: %v", err)
	}
	if store == nil {
		t.Fatal("expected credential store")
	}
	if err := store.CheckDuplicate("unbound-commitment"); err != nil {
		t.Fatalf("unexpected duplicate from empty durable store: %v", err)
	}
}

func TestBuildMobileMoicaRPConfigRequiresApprovalArtifacts(t *testing.T) {
	t.Setenv("MOBILEMOICA_RP_ENABLED", "true")
	t.Setenv("MOBILEMOICA_RP_ADAPTER_MODE", "contract")
	t.Setenv("MOBILEMOICA_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "mobilemoica.json"))

	_, _, err := buildMobileMoicaRPConfigFromEnv(false, time.Now, nil)
	if !errors.Is(err, errMobileMoicaRPConfigMissing) {
		t.Fatalf("expected missing approval config error, got %v", err)
	}
}

func TestBuildMobileMoicaRPConfigBuildsContractModeWhenGated(t *testing.T) {
	t.Setenv("MOBILEMOICA_RP_ENABLED", "true")
	t.Setenv("MOBILEMOICA_RP_ADAPTER_MODE", "contract")
	t.Setenv("MOBILEMOICA_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "mobilemoica.json"))
	t.Setenv("MOBILEMOICA_LEGAL_APPROVAL_ID", "legal-review")
	t.Setenv("MOBILEMOICA_PRIVACY_APPROVAL_ID", "privacy-review")
	t.Setenv("MOBILEMOICA_SECURITY_APPROVAL_ID", "security-review")
	t.Setenv("MOBILEMOICA_CONSTITUTION_APPROVAL_ID", "constitution-exception")
	t.Setenv("MOBILEMOICA_RETURN_URL", "trisaura://mobilemoica/callback")

	config, enabled, err := buildMobileMoicaRPConfigFromEnv(false, func() time.Time {
		return time.Date(2026, 5, 30, 12, 0, 0, 0, time.UTC)
	}, nil)
	if err != nil {
		t.Fatalf("build MobileMoica contract config: %v", err)
	}
	if !enabled || !config.Enabled {
		t.Fatalf("expected enabled config, got enabled=%v config=%+v", enabled, config)
	}
	if config.Store == nil || config.Broker == nil {
		t.Fatalf("expected store and broker: %+v", config)
	}

	request := provider.MobileMoicaStartRequest{
		OfferID:         "offer-1",
		State:           "state-1",
		HolderDID:       "did:plc:holder12345",
		NationalID:      "Z123000000",
		ConsentVersion:  "mobilemoica-rp-v1",
		ConsentCopyHash: "sha256:copy-hash",
		ReturnURL:       "trisaura://mobilemoica/callback",
		ExpiresAt:       time.Date(2026, 5, 30, 12, 5, 0, 0, time.UTC),
	}
	if _, err := config.Broker.Start(context.Background(), request); err != nil {
		t.Fatalf("start MobileMoica contract broker: %v", err)
	}
	_, err = config.Broker.Verify(context.Background(), request.OfferID, request.State)
	if !errors.Is(err, provider.ErrMobileMoicaResultPending) {
		t.Fatalf("contract mode must not synthesize success by default, got %v", err)
	}
}

func TestBuildMobileMoicaRPConfigAllowsSyntheticSuccessOnlyInMockMode(t *testing.T) {
	t.Setenv("MOBILEMOICA_RP_ENABLED", "true")
	t.Setenv("MOBILEMOICA_RP_ADAPTER_MODE", "contract")
	t.Setenv("MOBILEMOICA_RP_CONTRACT_AUTO_VERIFY", "true")
	t.Setenv("MOBILEMOICA_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "mobilemoica.json"))
	t.Setenv("MOBILEMOICA_LEGAL_APPROVAL_ID", "legal-review")
	t.Setenv("MOBILEMOICA_PRIVACY_APPROVAL_ID", "privacy-review")
	t.Setenv("MOBILEMOICA_SECURITY_APPROVAL_ID", "security-review")
	t.Setenv("MOBILEMOICA_CONSTITUTION_APPROVAL_ID", "constitution-exception")

	if _, _, err := buildMobileMoicaRPConfigFromEnv(false, time.Now, nil); !errors.Is(err, errMobileMoicaRPConfigMissing) {
		t.Fatalf("expected non-mock synthetic success config error, got %v", err)
	}

	config, enabled, err := buildMobileMoicaRPConfigFromEnv(true, time.Now, nil)
	if err != nil {
		t.Fatalf("expected mock synthetic success config: %v", err)
	}
	if !enabled || config.Broker == nil {
		t.Fatalf("expected enabled broker in mock mode: enabled=%v config=%+v", enabled, config)
	}
}

func TestBuildMobileMoicaRPConfigProductionModeFailsClosed(t *testing.T) {
	t.Setenv("MOBILEMOICA_RP_ENABLED", "true")
	t.Setenv("MOBILEMOICA_RP_ADAPTER_MODE", "production")
	t.Setenv("MOBILEMOICA_SESSION_STORE_PATH", filepath.Join(t.TempDir(), "mobilemoica.json"))
	t.Setenv("MOBILEMOICA_LEGAL_APPROVAL_ID", "legal-review")
	t.Setenv("MOBILEMOICA_PRIVACY_APPROVAL_ID", "privacy-review")
	t.Setenv("MOBILEMOICA_SECURITY_APPROVAL_ID", "security-review")
	t.Setenv("MOBILEMOICA_CONSTITUTION_APPROVAL_ID", "constitution-exception")

	_, _, err := buildMobileMoicaRPConfigFromEnv(false, time.Now, nil)
	if !errors.Is(err, provider.ErrMobileMoicaProductionUnavailable) {
		t.Fatalf("expected production unavailable error, got %v", err)
	}
}

func TestValidateCommitmentPepper(t *testing.T) {
	strong := "0123456789abcdef0123456789abcdef" // 32 bytes, no sentinel
	cases := []struct {
		name    string
		pepper  string
		wantErr bool
	}{
		{"strong 32-byte pepper", strong, false},
		{"too short", "short-pepper", true},
		{"dev sentinel full", "dev-pepper-not-for-production-000000000000", true},
		{"dev- prefix sentinel", "dev-abcdefghijklmnopqrstuvwxyz0123", true},
		{"changeme sentinel", "changeme-changeme-changeme-changeme", true},
		{"placeholder sentinel", "placeholder-placeholder-placeholder", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateCommitmentPepper(tc.pepper)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error for %q, got nil", tc.pepper)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error for %q: %v", tc.pepper, err)
			}
		})
	}
}

func TestValidateIssuerPrivateKeyHex(t *testing.T) {
	realKey := "61357fa541863df68f248a8c79244bf6652d96c1a43b42624c3f00988fd2d742"
	cases := []struct {
		name    string
		key     string
		wantErr bool
	}{
		{"valid 64-hex key", realKey, false},
		{"wrong length", "abcd", true},
		{"non-hex", "zz61b19deffe6a5f43e1a3b0e3f4c9b2a7d81f6e0c5b4a3928176554433221100", true},
		{"all zero", "0000000000000000000000000000000000000000000000000000000000000000", true},
		{"all ones (ff)", "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", true},
		{"repeated nibble", "1111111111111111111111111111111111111111111111111111111111111111", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateIssuerPrivateKeyHex(tc.key)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error for %q, got nil", tc.key)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error for %q: %v", tc.key, err)
			}
		})
	}
}

func TestProductionIssuerSignerRequiresKMSAndForbidsRawSeed(t *testing.T) {
	t.Setenv("ANSIBLE_APP_ENV", "prod")
	t.Setenv("K_SERVICE", "")
	t.Setenv("ISSUER_KMS_KEY_VERSION", "")
	validSeed := strings.Repeat("12", 32)

	_, err := buildIssuerSigner(context.Background(), vc.Config{
		IssuerDID: "did:web:issuer.example", PrivKeyHex: validSeed,
	}, false)
	if err == nil || !strings.Contains(err.Error(), "forbidden") {
		t.Fatalf("expected raw seed to be forbidden, got %v", err)
	}

	_, err = buildIssuerSigner(context.Background(), vc.Config{
		IssuerDID: "did:web:issuer.example",
	}, false)
	if err == nil || !strings.Contains(err.Error(), "ISSUER_KMS_KEY_VERSION is required") {
		t.Fatalf("expected KMS requirement, got %v", err)
	}
}

func TestDevelopmentIssuerSignerAllowsExplicitSeed(t *testing.T) {
	t.Setenv("ANSIBLE_APP_ENV", "dev")
	t.Setenv("K_SERVICE", "issuer-dev")
	t.Setenv("ISSUER_KMS_KEY_VERSION", "")
	seed := strings.Repeat("12", 32)
	signer, err := buildIssuerSigner(context.Background(), vc.Config{
		IssuerDID: "did:web:issuer-dev.example", PrivKeyHex: seed,
	}, false)
	if err != nil {
		t.Fatal(err)
	}
	if signer.KeyID() != "did:web:issuer-dev.example#key-1" {
		t.Fatalf("unexpected key id %q", signer.KeyID())
	}
}
