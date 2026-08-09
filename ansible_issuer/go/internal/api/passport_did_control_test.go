package api

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHTTPPassportDIDControlVerifierAcceptsOnlyCurrentHolderSignature(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	const handle = "alice.elix.cool"
	did := deriveInitialDID(handle, hex.EncodeToString(publicKey), "hardware", "ed25519")
	canonicalBody := `{"type":"io.trisaura.identity.anchor","did":"` + did + `"}`
	anchorSignature := hex.EncodeToString(ed25519.Sign(privateKey, []byte(canonicalBody)))
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/identity/anchor/"+did {
			t.Fatalf("unexpected resolver path %q", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"did": did, "handle": handle, "identity_key": hex.EncodeToString(publicKey), "identity_key_algorithm": "ed25519", "custody_class": "hardware", "reason": "initial", "prev_anchor_cid": nil, "canonical_body": canonicalBody, "sig": anchorSignature,
		})
	}))
	defer server.Close()

	auth := PassportIssueAuthorization{
		DID: did, ChallengeID: "challenge", ChallengeNonce: "nonce", ChallengeIssuer: "https://issuer.elix.cool",
		ChallengeScope: passportScope, Nationality: "TWN", ZKPProof: `{"proof":"opaque"}`,
		ZKPCircuitVersion: passportCircuitVersion, VerificationKeyHash: "sha256:pinned",
	}
	payload, err := auth.canonicalPayload()
	if err != nil {
		t.Fatal(err)
	}
	auth.SignatureHex = hex.EncodeToString(ed25519.Sign(privateKey, payload))
	verifier, err := NewHTTPPassportDIDControlVerifier(server.URL, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := verifier.VerifyPassportIssue(auth); err != nil {
		t.Fatalf("valid holder signature rejected: %v", err)
	}

	// Every bound field, including the opaque proof digest, is integrity
	// protected by the holder signature.
	auth.ZKPProof = `{"proof":"substituted"}`
	if err := verifier.VerifyPassportIssue(auth); err == nil {
		t.Fatal("substituted proof was accepted")
	}
}

func TestHTTPPassportDIDControlVerifierAcceptsSelfCertifyingV2Identity(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	const handle = "alice.elix.cool"
	did := deriveInitialDID(handle, hex.EncodeToString(publicKey), "hardware", "ed25519")
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasPrefix(r.URL.Path, "/api/v1/identity/anchor/"):
			w.WriteHeader(http.StatusNotFound)
		case strings.HasPrefix(r.URL.Path, "/api/v1/identity/public-key/"):
			requestedDID := strings.TrimPrefix(r.URL.Path, "/api/v1/identity/public-key/")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"did": requestedDID, "public_key_hex": hex.EncodeToString(publicKey), "signing_algorithm": "ed25519",
			})
		case strings.HasPrefix(r.URL.Path, "/api/v1/identity/handle/"):
			requestedDID := strings.TrimPrefix(r.URL.Path, "/api/v1/identity/handle/")
			_ = json.NewEncoder(w).Encode(map[string]any{"did": requestedDID, "handle": handle})
		default:
			t.Fatalf("unexpected resolver path %q", r.URL.Path)
		}
	}))
	defer server.Close()

	auth := PassportIssueAuthorization{
		DID: did, ChallengeID: "challenge", ChallengeNonce: "nonce", ChallengeIssuer: "https://issuer.elix.cool",
		ChallengeScope: passportScope, Nationality: "TWN", ZKPProof: `{"proof":"opaque"}`,
		ZKPCircuitVersion: passportCircuitVersion, VerificationKeyHash: "sha256:pinned",
	}
	payload, err := auth.canonicalPayload()
	if err != nil {
		t.Fatal(err)
	}
	auth.SignatureHex = hex.EncodeToString(ed25519.Sign(privateKey, payload))
	verifier, err := NewHTTPPassportDIDControlVerifier(server.URL, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := verifier.VerifyPassportIssue(auth); err != nil {
		t.Fatalf("valid V2 holder signature rejected: %v", err)
	}

	// The key endpoint cannot substitute an arbitrary key/handle pair: the DID
	// must still self-certify from exactly those public fields.
	did = "did:elix:forged"
	auth.DID = did
	if err := verifier.VerifyPassportIssue(auth); err == nil {
		t.Fatal("non-self-certifying V2 identity was accepted")
	}
}

func TestHTTPPassportDIDControlVerifierRejectsResolverDIDMismatch(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"did":"did:elix:wrongwrongwrongwrongwrongwo","public_key_hex":"00","signing_algorithm":"ed25519"}`))
	}))
	defer server.Close()
	verifier, err := NewHTTPPassportDIDControlVerifier(strings.TrimRight(server.URL, "/"), server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := verifier.VerifyPassportIssue(PassportIssueAuthorization{DID: "did:elix:abcdefghijklmnopqrstuvwxyz", SignatureHex: "00"}); err == nil {
		t.Fatal("resolver DID mismatch was accepted")
	}
}
