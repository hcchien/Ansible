package main

import (
	"log"
	"net/http"
	"os"
	"strconv"
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
		log.Fatal("real TW identity provider not yet integrated — set MOCK_MODE=true for dev")
	}

	mux := http.NewServeMux()
	api.NewHandler(otp.NewStore(otpTTL), prov, issuer, pepper, mockMode).Register(mux)

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
