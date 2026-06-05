package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/trisaura/ansible_issuer/internal/api"
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
	mockMode := os.Getenv("MOCK_MODE") == "true"
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
	handler := api.NewHandler(otp.NewStore(otpTTL), prov, issuer, pepper, mockMode)
	configureTWProvider(handler, mockMode, pgPool)
	configureMobileMoicaRP(handler, mockMode, pgPool)
	handler.Register(mux)

	srv := &http.Server{Addr: ":" + port, Handler: mux}

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

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("required env var %s is not set", key)
	}
	return v
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
