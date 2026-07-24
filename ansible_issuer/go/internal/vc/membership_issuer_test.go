package vc

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestMembershipCredentialIsMinimalAndHardwareHolderBound(t *testing.T) {
	seed := make([]byte, ed25519.SeedSize)
	if _, err := rand.Read(seed); err != nil {
		t.Fatal(err)
	}
	signer, err := NewEd25519SeedSigner("did:web:party.example#key-1", hex.EncodeToString(seed))
	if err != nil {
		t.Fatal(err)
	}
	issued, err := IssueMembershipJWT(signer, MembershipIssueRequest{
		IssuerDID: "did:web:party.example", IssuerURL: "https://issuer.example/tenants/party",
		HolderPairwiseDID: "did:peer:holder", HolderJWK: map[string]string{"kty": "EC", "crv": "P-256", "x": strings.Repeat("x", 43), "y": strings.Repeat("y", 43)},
		MembershipClass: "member", ForumHostID: "host-local-dev", BoardID: "board-party-members", StatusListIndex: 7, StatusListBaseURL: "https://issuer.example/tenants/party/status",
		Now: time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC),
	})
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(issued.JWT, ".")
	if len(parts) != 3 {
		t.Fatal("not a compact JWT")
	}
	claimsJSON, _ := base64.RawURLEncoding.DecodeString(parts[1])
	var claims map[string]any
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		t.Fatal(err)
	}
	if claims["cnf"] == nil || strings.Contains(string(claimsJSON), "membership_number") || strings.Contains(string(claimsJSON), "legal_name") {
		t.Fatalf("credential is not minimally holder-bound: %s", claimsJSON)
	}
	if !strings.Contains(string(claimsJSON), `"board_id":"board-party-members"`) {
		t.Fatalf("credential is not board-bound: %s", claimsJSON)
	}
	if !strings.Contains(string(claimsJSON), `"forum_host_id":"host-local-dev"`) {
		t.Fatalf("credential is not host-bound: %s", claimsJSON)
	}
	if !ed25519.Verify(signer.PublicKey().(ed25519.PublicKey), []byte(parts[0]+"."+parts[1]), mustDecodeBase64(t, parts[2])) {
		t.Fatal("JWT signature invalid")
	}
}

func mustDecodeBase64(t *testing.T, value string) []byte {
	t.Helper()
	decoded, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}
