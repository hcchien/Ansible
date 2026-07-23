package api

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

func TestHTTPPassportBindingVerifierForwardsChallengeAndUsesVerifiedOutputs(t *testing.T) {
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body["challenge_nonce"] != "nonce-1" || body["did"] != "did:plc:abcdefghijklmnop" {
			t.Fatalf("challenge binding missing: %#v", body)
		}
		response, _ := json.Marshal(map[string]any{
			"verified":             true,
			"nationality":          "TWN",
			"national_id_hash":     "different-national-id",
			"passport_number_hash": "passport-number-hash",
		})
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(response)),
			Header:     make(http.Header),
		}, nil
	})}
	verifier, err := NewHTTPPassportBindingVerifier("https://verifier.example", client)
	if err != nil {
		t.Fatal(err)
	}
	result, err := verifier.VerifyPassportBinding(PassportBindingProof{
		DID: "did:plc:abcdefghijklmnop", ChallengeID: "challenge-1",
		ChallengeNonce: "nonce-1", ChallengeIssuer: "https://issuer.example",
		ChallengeScope: "elix-passport-personhood-v1", Nationality: "TWN",
		NationalIDHash: "national-id-hash", PassportNumberHash: "passport-number-hash",
		ZKPProof: `{"proofs":[]}`, ZKPCircuitVersion: "0.20.0",
		VerificationKeyHash: "sha256:test",
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.NationalIDHash != "different-national-id" {
		t.Fatalf("issuer must use verifier-derived output, got %#v", result)
	}
}

func TestHTTPPassportBindingVerifierAddsWorkloadIdentityToken(t *testing.T) {
	t.Setenv("PASSPORT_VERIFIER_AUDIENCE", "https://verifier-service.run.app")
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		if got := r.Header.Get("authorization"); got != "Bearer workload-token" {
			t.Fatalf("authorization header = %q", got)
		}
		response, _ := json.Marshal(map[string]any{
			"verified":             true,
			"nationality":          "TWN",
			"national_id_hash":     "national-id-hash",
			"passport_number_hash": "passport-number-hash",
		})
		return &http.Response{
			StatusCode: http.StatusOK,
			Body:       io.NopCloser(bytes.NewReader(response)),
			Header:     make(http.Header),
		}, nil
	})}
	verifier, err := NewHTTPPassportBindingVerifier("https://verifier.example", client)
	if err != nil {
		t.Fatal(err)
	}
	verifier.identityToken = func(_ context.Context, audience string) (string, error) {
		if audience != "https://verifier-service.run.app" {
			t.Fatalf("audience = %q", audience)
		}
		return "workload-token", nil
	}
	_, err = verifier.VerifyPassportBinding(PassportBindingProof{
		DID: "did:plc:abcdefghijklmnop", ChallengeID: "challenge-1",
		ChallengeNonce: "nonce-1", ChallengeIssuer: "https://issuer.example",
		ChallengeScope: "elix-passport-personhood-v1", Nationality: "TWN",
		NationalIDHash: "national-id-hash", PassportNumberHash: "passport-number-hash",
		ZKPProof: `{"proofs":[]}`, ZKPCircuitVersion: "0.20.0",
		VerificationKeyHash: "sha256:test",
	})
	if err != nil {
		t.Fatal(err)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}
