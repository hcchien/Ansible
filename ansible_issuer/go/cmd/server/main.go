package main

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/otp"
	"github.com/trisaura/ansible_issuer/internal/pgstore"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

func main() {
	cfg := vc.Config{
		IssuerDID:  mustEnv("ISSUER_DID"),
		IssuerURL:  mustEnv("ISSUER_URL"),
		PrivKeyHex: mustEnv("ISSUER_PRIVATE_KEY_HEX"),
		TTLDays:    envInt("VC_TTL_DAYS", 90),
	}
	pepper := mustEnv("SUBJECT_COMMITMENT_PEPPER")
	previousPeppers := splitCSV(os.Getenv("SUBJECT_COMMITMENT_PEPPER_PREVIOUS"))
	mockMode := os.Getenv("MOCK_MODE") == "true"
	if mockMode && isProdLikeEnvironment(cfg.IssuerURL) {
		log.Fatal("MOCK_MODE=true refused: this looks like a production deployment " +
			"(K_SERVICE set or a non-local HTTPS ISSUER_URL). Mock mode disables real " +
			"identity verification — it issues credentials for any email and returns the " +
			"OTP in the HTTP response. Unset MOCK_MODE.")
	}

	// Reject weak/known secrets at boot outside dev. A dev-sentinel pepper or a
	// placeholder private key would silently make commitments/proofs forgeable,
	// so fail closed rather than start. Skipped under MOCK_MODE (dev only).
	if !mockMode {
		if err := validateCommitmentPepper(pepper); err != nil {
			log.Fatalf("SUBJECT_COMMITMENT_PEPPER rejected: %v", err)
		}
		for _, prev := range previousPeppers {
			if err := validateCommitmentPepper(prev); err != nil {
				log.Fatalf("SUBJECT_COMMITMENT_PEPPER_PREVIOUS entry rejected: %v", err)
			}
		}
		if err := validateIssuerPrivateKeyHex(cfg.PrivKeyHex); err != nil {
			log.Fatalf("ISSUER_PRIVATE_KEY_HEX rejected: %v", err)
		}
	}
	peppers := commitment.NewSet(pepper, previousPeppers)
	otpTTL := time.Duration(envInt("OTP_TTL_SECONDS", 300)) * time.Second
	port := os.Getenv("PORT")
	if port == "" {
		port = "4002"
	}

	// One shared connection pool for all durable issuer stores (personhood +
	// provider sessions) when a database is configured outside mock mode.
	var pgPool *pgxpool.Pool
	if databaseURL := os.Getenv("DATABASE_URL"); !mockMode && databaseURL != "" {
		pool, err := pgstore.Connect(context.Background(), databaseURL)
		if err != nil {
			log.Fatal(err)
		}
		if err := pgstore.EnsureSchema(context.Background(), pool); err != nil {
			log.Fatal(err)
		}
		defer pool.Close()
		pgPool = pool
		log.Println("issuer durable stores: PostgreSQL")
	}

	store, err := buildCredentialStoreFromEnv(mockMode, pgPool)
	if err != nil {
		log.Fatal(err)
	}
	issuer, err := vc.NewIssuer(cfg, store)
	if err != nil {
		log.Fatalf("issuer init: %v", err)
	}

	var prov provider.TwIdentityProvider
	if mockMode {
		log.Println("MOCK_MODE=true — using mock identity provider")
		prov = provider.Mock{}
	} else {
		prov = disabledIdentityProvider{}
	}

	mux := http.NewServeMux()
	handler := api.NewHandler(otp.NewStore(otpTTL), prov, issuer, peppers, mockMode)
	configureTWProvider(handler, mockMode, pgPool)
	configureMobileMoicaRP(handler, mockMode, pgPool)
	// Passport issuance is intentionally left UNCONFIGURED: there is no real
	// PassportBindingVerifier (a ZKP/NFC verifier) in this service yet, and we
	// will not wire a fake one. handler.ConfigurePassport is therefore never
	// called, so POST /api/v1/vc/passport/issue fails closed with 503
	// passport_verifier_unconfigured (see handler.passportIssue). This is a
	// deliberate scope limit, not an oversight — do not enable it until a
	// genuine verifier exists.
	log.Println("passport issuance disabled: no PassportBindingVerifier configured (fails closed 503)")
	if adminToken := os.Getenv("ISSUER_ADMIN_TOKEN"); adminToken != "" {
		handler.ConfigureAdmin(adminToken)
		log.Println("credential revocation endpoint enabled (bearer-token guarded)")
	} else {
		log.Println("credential revocation endpoint disabled: set ISSUER_ADMIN_TOKEN to enable")
	}
	handler.Register(mux)

	// Bound every phase of a connection's lifetime so a slow or idle client
	// cannot pin a connection (slowloris). ReadHeaderTimeout is the key
	// slowloris guard; the rest cap total request/response and idle time.
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// On Cloud Run the platform sends SIGTERM before stopping the instance.
	// Drain in-flight requests so an issuance whose durable store write is in
	// progress completes before exit, rather than being cut off by SIGKILL.
	idleClosed := make(chan struct{})
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
		<-sigCh
		log.Println("shutdown signal received, draining connections")
		ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("graceful shutdown error: %v", err)
		}
		close(idleClosed)
	}()

	log.Printf("ansible_issuer (go) listening on :%s", port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
	<-idleClosed
}

// isProdLikeEnvironment reports whether the process appears to be running in a
// managed/production deployment, in which case MOCK_MODE must be refused. Two
// signals are used: Cloud Run injects K_SERVICE into every container, and a
// production issuer is served from a non-local HTTPS ISSUER_URL. Staging on
// Cloud Run uses the `contract` adapter (not mock mode), so K_SERVICE being set
// is a sufficient guard there too.
func isProdLikeEnvironment(issuerURL string) bool {
	if os.Getenv("K_SERVICE") != "" {
		return true
	}
	u, err := url.Parse(issuerURL)
	if err != nil || u.Scheme != "https" {
		return false
	}
	host := u.Hostname()
	if host == "" || host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return false
	}
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() {
			return false
		}
	}
	return true
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required env var %s is not set", key)
	}
	return v
}

// devSecretSentinels are substrings that mark a value as a development
// placeholder that must never reach production.
var devSecretSentinels = []string{
	"dev-pepper-not-for-production",
	"dev-",
	"changeme",
	"placeholder",
	"example",
	"test-pepper",
}

// minPepperBytes is the minimum accepted pepper length. HMAC-SHA256 keys shorter
// than the block-relevant 32 bytes materially reduce brute-force cost, and a
// short pepper is a strong sign of a hand-typed dev value.
const minPepperBytes = 32

// validateCommitmentPepper rejects a commitment pepper that is too short or
// matches a known dev sentinel, since either makes subject commitments (and thus
// the one-person-one-credential guarantee) forgeable.
func validateCommitmentPepper(pepper string) error {
	if len(pepper) < minPepperBytes {
		return fmt.Errorf("pepper must be at least %d bytes, got %d", minPepperBytes, len(pepper))
	}
	lower := strings.ToLower(pepper)
	for _, s := range devSecretSentinels {
		if strings.Contains(lower, s) {
			return fmt.Errorf("pepper contains dev sentinel %q", s)
		}
	}
	return nil
}

// validateIssuerPrivateKeyHex rejects a signing key that is not a well-formed
// 32-byte Ed25519 seed, or that is an obvious placeholder (all-zero, all-one, or
// a repeated nibble), which would make issued proofs trivially forgeable.
func validateIssuerPrivateKeyHex(keyHex string) error {
	if len(keyHex) != 64 {
		return fmt.Errorf("key must be 64 hex chars (32-byte Ed25519 seed), got %d chars", len(keyHex))
	}
	seed, err := hex.DecodeString(keyHex)
	if err != nil {
		return fmt.Errorf("key is not valid hex: %w", err)
	}
	allZero, allOne := true, true
	for _, b := range seed {
		if b != 0x00 {
			allZero = false
		}
		if b != 0xff {
			allOne = false
		}
	}
	if allZero {
		return errors.New("key is all-zero placeholder")
	}
	if allOne {
		return errors.New("key is all-ones placeholder")
	}
	// A key that is a single repeated hex nibble (e.g. "1111...", "abab...") is
	// almost certainly a hand-typed placeholder, not real key material.
	if isRepeatedNibble(keyHex) {
		return errors.New("key is a repeated-nibble placeholder")
	}
	return nil
}

func isRepeatedNibble(keyHex string) bool {
	if keyHex == "" {
		return false
	}
	first := keyHex[0]
	for i := 1; i < len(keyHex); i++ {
		if keyHex[i] != first {
			return false
		}
	}
	return true
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

type disabledIdentityProvider struct{}

func (disabledIdentityProvider) ProviderSubject(string, string) (string, error) {
	return "", errors.New("legacy identity provider disabled")
}

var errTWProviderConfigMissing = errors.New("TW provider config missing")
var errMobileMoicaRPConfigMissing = errors.New("MobileMoica RP config missing")
var errPersonhoodBindingStoreConfigMissing = errors.New("personhood binding store config missing")

func configureTWProvider(handler *api.Handler, mockMode bool, pool *pgxpool.Pool) {
	config, err := buildTWProviderConfigFromEnv(mockMode, time.Now, pool)
	if err != nil {
		log.Fatal(err)
	}
	handler.ConfigureTWProvider(config)
	log.Printf("TW provider flow enabled with auth URL %s", config.BaseAuthURL)
}

func configureMobileMoicaRP(handler *api.Handler, mockMode bool, pool *pgxpool.Pool) {
	config, enabled, err := buildMobileMoicaRPConfigFromEnv(mockMode, time.Now, pool)
	if err != nil {
		log.Fatal(err)
	}
	if !enabled {
		return
	}
	handler.ConfigureMobileMoicaRP(config)
	log.Printf("MobileMoica RP flow enabled in explicit-disclosure mode")
}

// providerSessionStore returns a Postgres-backed session store when a pool is
// configured (horizontal scaling), else a file-backed one.
func providerSessionStore(pool *pgxpool.Pool, namespace, storePath string, now func() time.Time) (provider.SessionStore, error) {
	if pool != nil {
		return provider.NewPostgresSessionStore(pool, namespace, now), nil
	}
	return provider.NewFileSessionStore(storePath, now)
}

func buildCredentialStoreFromEnv(mockMode bool, pool *pgxpool.Pool) (vc.CredentialStore, error) {
	// PostgreSQL when configured so the issuer can scale horizontally;
	// duplicate-prevention is enforced by DB unique constraints across instances.
	if pool != nil {
		log.Println("personhood binding store: PostgreSQL")
		return vc.NewPostgresStore(pool), nil
	}

	storePath := os.Getenv("PERSONHOOD_BINDING_STORE_PATH")
	if storePath == "" {
		if mockMode {
			return vc.NewStore(), nil
		}
		return nil, fmt.Errorf("%w: PERSONHOOD_BINDING_STORE_PATH", errPersonhoodBindingStoreConfigMissing)
	}
	store, err := vc.NewFileStore(storePath)
	if err != nil {
		return nil, fmt.Errorf("personhood binding store init: %w", err)
	}
	return store, nil
}

func buildTWProviderConfigFromEnv(mockMode bool, now func() time.Time, pool *pgxpool.Pool) (api.TWProviderConfig, error) {
	required := []string{"TW_PROVIDER_AUTH_URL"}
	// The session store path is only needed for the file-backed store.
	if pool == nil {
		required = append(required, "TW_PROVIDER_SESSION_STORE_PATH")
	}
	if !mockMode {
		required = append(required, "TW_PROVIDER_ADAPTER_MODE")
	}
	missing := missingEnv(required)
	if len(missing) > 0 && !mockMode {
		return api.TWProviderConfig{}, fmt.Errorf("%w: %s", errTWProviderConfigMissing, strings.Join(missing, ", "))
	}

	storePath := os.Getenv("TW_PROVIDER_SESSION_STORE_PATH")
	authURL := os.Getenv("TW_PROVIDER_AUTH_URL")
	adapterMode := os.Getenv("TW_PROVIDER_ADAPTER_MODE")
	sharedSecret := os.Getenv("TW_PROVIDER_SHARED_SECRET")
	audience := os.Getenv("TW_PROVIDER_AUDIENCE")
	if mockMode {
		if storePath == "" {
			storePath = filepath.Join(os.TempDir(), "ansible_issuer_tw_provider_sessions.json")
		}
		if authURL == "" {
			authURL = "https://provider.example/authorize"
		}
		if adapterMode == "" {
			adapterMode = string(provider.VerifierAdapterContract)
		}
		if sharedSecret == "" {
			sharedSecret = "dev-only-tw-provider-secret"
		}
		if audience == "" {
			audience = "trisaura-issuer-dev"
		}
	}

	if adapterMode == string(provider.VerifierAdapterContract) && !mockMode {
		contractMissing := missingEnv([]string{"TW_PROVIDER_SHARED_SECRET", "TW_PROVIDER_AUDIENCE"})
		if len(contractMissing) > 0 {
			return api.TWProviderConfig{}, fmt.Errorf("%w: %s", errTWProviderConfigMissing, strings.Join(contractMissing, ", "))
		}
	}

	store, err := providerSessionStore(pool, "tw", storePath, now)
	if err != nil {
		return api.TWProviderConfig{}, fmt.Errorf("TW provider session store init: %w", err)
	}
	retention := time.Duration(envInt("TW_PROVIDER_RETENTION_SECONDS", 86400)) * time.Second
	if err := store.CleanupExpired(retention); err != nil {
		return api.TWProviderConfig{}, fmt.Errorf("TW provider session cleanup: %w", err)
	}
	verifier, err := provider.NewProofVerifierAdapter(provider.VerifierAdapterConfig{
		Mode:                   provider.VerifierAdapterMode(adapterMode),
		SharedSecret:           sharedSecret,
		Audience:               audience,
		Now:                    now,
		ProductionTrustAnchors: splitCSV(os.Getenv("TW_PROVIDER_PRODUCTION_TRUST_ANCHORS")),
		ProductionAudience:     os.Getenv("TW_PROVIDER_PRODUCTION_AUDIENCE"),
	})
	if err != nil {
		return api.TWProviderConfig{}, err
	}

	return api.TWProviderConfig{
		SessionStore: store,
		Verifier:     verifier,
		BaseAuthURL:  authURL,
		TTL:          time.Duration(envInt("TW_PROVIDER_SESSION_TTL_SECONDS", 300)) * time.Second,
		Retention:    retention,
	}, nil
}

func buildMobileMoicaRPConfigFromEnv(mockMode bool, now func() time.Time, pool *pgxpool.Pool) (api.MobileMoicaRPConfig, bool, error) {
	if os.Getenv("MOBILEMOICA_RP_ENABLED") != "true" {
		return api.MobileMoicaRPConfig{}, false, nil
	}

	required := []string{
		"MOBILEMOICA_RP_ADAPTER_MODE",
		"MOBILEMOICA_LEGAL_APPROVAL_ID",
		"MOBILEMOICA_PRIVACY_APPROVAL_ID",
		"MOBILEMOICA_SECURITY_APPROVAL_ID",
		"MOBILEMOICA_CONSTITUTION_APPROVAL_ID",
	}
	if !mockMode && pool == nil {
		required = append(required, "MOBILEMOICA_SESSION_STORE_PATH")
	}
	missing := missingEnv(required)
	if len(missing) > 0 {
		return api.MobileMoicaRPConfig{}, false, fmt.Errorf("%w: %s", errMobileMoicaRPConfigMissing, strings.Join(missing, ", "))
	}

	storePath := os.Getenv("MOBILEMOICA_SESSION_STORE_PATH")
	if storePath == "" {
		storePath = filepath.Join(os.TempDir(), "ansible_issuer_mobilemoica_rp_sessions.json")
	}
	store, err := providerSessionStore(pool, "mobilemoica", storePath, now)
	if err != nil {
		return api.MobileMoicaRPConfig{}, false, fmt.Errorf("MobileMoica RP session store init: %w", err)
	}
	retention := time.Duration(envInt("MOBILEMOICA_RETENTION_SECONDS", 86400)) * time.Second
	if err := store.CleanupExpired(retention); err != nil {
		return api.MobileMoicaRPConfig{}, false, fmt.Errorf("MobileMoica RP session cleanup: %w", err)
	}

	approval := provider.MobileMoicaApprovalConfig{
		LegalApprovalID:        os.Getenv("MOBILEMOICA_LEGAL_APPROVAL_ID"),
		PrivacyApprovalID:      os.Getenv("MOBILEMOICA_PRIVACY_APPROVAL_ID"),
		SecurityApprovalID:     os.Getenv("MOBILEMOICA_SECURITY_APPROVAL_ID"),
		ConstitutionApprovalID: os.Getenv("MOBILEMOICA_CONSTITUTION_APPROVAL_ID"),
	}
	if err := provider.ValidateMobileMoicaApprovalConfig(approval); err != nil {
		return api.MobileMoicaRPConfig{}, false, fmt.Errorf("%w: approval artifacts", errMobileMoicaRPConfigMissing)
	}

	returnURL := os.Getenv("MOBILEMOICA_RETURN_URL")
	if returnURL == "" {
		returnURL = "trisaura://mobilemoica/callback"
	}
	var broker provider.MobileMoicaRPBroker
	switch os.Getenv("MOBILEMOICA_RP_ADAPTER_MODE") {
	case "contract":
		contractAutoVerify := os.Getenv("MOBILEMOICA_RP_CONTRACT_AUTO_VERIFY") == "true"
		if contractAutoVerify && !mockMode {
			return api.MobileMoicaRPConfig{}, false, fmt.Errorf("%w: MOBILEMOICA_RP_CONTRACT_AUTO_VERIFY requires MOCK_MODE=true", errMobileMoicaRPConfigMissing)
		}
		broker = provider.NewContractMobileMoicaRPBroker(provider.ContractMobileMoicaRPConfig{
			ReturnURL:  returnURL,
			Now:        now,
			AutoVerify: contractAutoVerify,
		})
	case "production":
		return api.MobileMoicaRPConfig{}, false, provider.ErrMobileMoicaProductionUnavailable
	default:
		return api.MobileMoicaRPConfig{}, false, fmt.Errorf("%w: MOBILEMOICA_RP_ADAPTER_MODE", errMobileMoicaRPConfigMissing)
	}

	return api.MobileMoicaRPConfig{
		Enabled:   true,
		Store:     store,
		Broker:    broker,
		Approval:  approval,
		ReturnURL: returnURL,
		TTL:       time.Duration(envInt("MOBILEMOICA_SESSION_TTL_SECONDS", 300)) * time.Second,
	}, true, nil
}

func missingEnv(keys []string) []string {
	var missing []string
	for _, key := range keys {
		if os.Getenv(key) == "" {
			missing = append(missing, key)
		}
	}
	return missing
}

func splitCSV(value string) []string {
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	var result []string
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
}
