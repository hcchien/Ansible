package api_test

import (
	"net/http"
	"strings"
	"testing"
)

func TestDIDDocumentServed(t *testing.T) {
	h := newTestHandler(t)
	w := call(h, http.MethodGet, "/.well-known/did.json", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body)
	}

	doc := bodyJSON(t, w)

	if doc["id"] != "did:web:issuer.trisaura.io" {
		t.Fatalf("unexpected id: %v", doc["id"])
	}

	vms, ok := doc["verificationMethod"].([]any)
	if !ok || len(vms) != 1 {
		t.Fatalf("expected one verificationMethod, got: %v", doc["verificationMethod"])
	}
	vm, ok := vms[0].(map[string]any)
	if !ok {
		t.Fatalf("verificationMethod not an object: %v", vms[0])
	}
	if vm["id"] != "did:web:issuer.trisaura.io#key-1" {
		t.Fatalf("unexpected vm id: %v", vm["id"])
	}
	if vm["type"] != "Multikey" {
		t.Fatalf("unexpected vm type: %v", vm["type"])
	}
	if vm["controller"] != "did:web:issuer.trisaura.io" {
		t.Fatalf("unexpected controller: %v", vm["controller"])
	}
	pkm, ok := vm["publicKeyMultibase"].(string)
	if !ok || !strings.HasPrefix(pkm, "z") {
		t.Fatalf("publicKeyMultibase must be base58-btc multibase, got: %v", vm["publicKeyMultibase"])
	}

	am, ok := doc["assertionMethod"].([]any)
	if !ok || len(am) != 1 || am[0] != "did:web:issuer.trisaura.io#key-1" {
		t.Fatalf("unexpected assertionMethod: %v", doc["assertionMethod"])
	}
}
