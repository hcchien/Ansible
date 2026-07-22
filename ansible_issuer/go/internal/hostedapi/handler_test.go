package hostedapi

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/trisaura/ansible_issuer/internal/hostedissuer"
)

func TestManifestUsesStableSnakeCaseAndNeverExportsPEM(t *testing.T) {
	now := time.Date(2026, 7, 22, 0, 0, 0, 0, time.UTC)
	store := hostedissuer.NewMemoryStore()
	tenant := hostedissuer.Tenant{
		ID: "party", OrganizationDID: "did:web:party.example", ServiceSlug: "party",
		Status: hostedissuer.TenantDraft, Threshold: 1, PolicyVersion: 1, CreatedAt: now,
	}
	owner := hostedissuer.Administrator{
		DID: "did:example:owner", Role: "owner", State: "active",
		SigningAlgorithm: "p256-sha256", PublicKeyHex: "04", Custody: "hardware",
	}
	if err := store.BootstrapTenant(tenant, owner); err != nil {
		t.Fatal(err)
	}
	publicKey, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(publicKey)
	if err != nil {
		t.Fatal(err)
	}
	publicPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))
	if err := store.PutSigningKey("party", hostedissuer.SigningKey{
		ID: "key-1", KMSKeyVersion: "kms/1", PublicKeyPEM: publicPEM,
		Algorithm: "Ed25519", ProtectionLevel: "HSM", State: "active", Version: 1, CreatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	delegation := hostedissuer.Delegation{
		ID: "delegation-1", SigningKeyID: "key-1", Sequence: 1,
		PayloadHash: "hash", NotBefore: now.Add(-time.Minute), ExpiresAt: now.Add(time.Hour),
	}
	if err := store.ProposeDelegation("party", delegation); err != nil {
		t.Fatal(err)
	}
	if err := store.ApproveDelegation("party", "delegation-1", owner.DID, []byte("signature")); err != nil {
		t.Fatal(err)
	}
	if err := store.ActivateDelegation("party", "delegation-1", now); err != nil {
		t.Fatal(err)
	}

	mux := http.NewServeMux()
	NewHandler(store, nil, nil, nil, nil, nil, func() time.Time { return now }).Register(mux)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/hosted-issuers/party/manifest", nil)
	response := httptest.NewRecorder()
	mux.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	encoded := response.Body.String()
	if _, ok := body["tenant"].(map[string]any)["organization_did"]; !ok {
		t.Fatalf("missing snake_case organization_did: %s", encoded)
	}
	if _, leaked := body["tenant"].(map[string]any)["OrganizationDID"]; leaked {
		t.Fatalf("Go field name leaked into API: %s", encoded)
	}
	if contains := json.Valid(response.Body.Bytes()) && (stringContains(encoded, "PUBLIC KEY") || stringContains(encoded, "kms/1")); contains {
		t.Fatalf("private control-plane key metadata leaked: %s", encoded)
	}
}

func stringContains(value, substring string) bool {
	for i := 0; i+len(substring) <= len(value); i++ {
		if value[i:i+len(substring)] == substring {
			return true
		}
	}
	return false
}
