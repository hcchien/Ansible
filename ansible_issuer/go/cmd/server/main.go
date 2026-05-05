package main

import (
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/trisaura/ansible_issuer/internal/api"
	"github.com/trisaura/ansible_issuer/internal/otp"
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

	store := vc.NewStore()
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
	configureTWProvider(handler, mockMode)
	handler.Register(mux)

	log.Printf("ansible_issuer (go) listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
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

func configureTWProvider(handler *api.Handler, mockMode bool) {
	required := []string{
		"TW_PROVIDER_SESSION_STORE_PATH",
		"TW_PROVIDER_AUTH_URL",
		"TW_PROVIDER_SHARED_SECRET",
		"TW_PROVIDER_AUDIENCE",
	}
	missing := missingEnv(required)
	if len(missing) > 0 && !mockMode {
		log.Fatalf("TW provider config missing: %s", strings.Join(missing, ", "))
	}

	storePath := os.Getenv("TW_PROVIDER_SESSION_STORE_PATH")
	authURL := os.Getenv("TW_PROVIDER_AUTH_URL")
	sharedSecret := os.Getenv("TW_PROVIDER_SHARED_SECRET")
	audience := os.Getenv("TW_PROVIDER_AUDIENCE")
	if mockMode {
		if storePath == "" {
			storePath = filepath.Join(os.TempDir(), "ansible_issuer_tw_provider_sessions.json")
		}
		if authURL == "" {
			authURL = "https://provider.example/authorize"
		}
		if sharedSecret == "" {
			sharedSecret = "dev-only-tw-provider-secret"
		}
		if audience == "" {
			audience = "trisaura-issuer-dev"
		}
	}

	store, err := provider.NewFileSessionStore(storePath, time.Now)
	if err != nil {
		log.Fatalf("TW provider session store init: %v", err)
	}
	handler.ConfigureTWProvider(api.TWProviderConfig{
		SessionStore: store,
		Verifier: provider.NewContractProofVerifier(provider.ContractProofConfig{
			SharedSecret: sharedSecret,
			Audience:     audience,
			Now:          time.Now,
		}),
		BaseAuthURL: authURL,
		TTL:         time.Duration(envInt("TW_PROVIDER_SESSION_TTL_SECONDS", 300)) * time.Second,
	})
	log.Printf("TW provider flow enabled with auth URL %s", authURL)
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
