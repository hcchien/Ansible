package hostedissuer

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestAdminWebAuthnRegistrationRequiresUVAndSingleUseServerSession(t *testing.T) {
	now := time.Now().UTC()
	store := NewMemoryAdminWebAuthnStore()
	capabilities := NewAdminCapabilityService(NewMemoryAdminCapabilityStore(), func() time.Time { return now })
	service, err := NewAdminWebAuthnService("issuer.example", []string{"https://issuer.example"}, store, capabilities, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	ceremonyID, options, err := service.BeginRegistration("tenant-a", "did:plc:admin")
	if err != nil {
		t.Fatal(err)
	}
	if !store.sessions[ceremonyID].ExpiresAt.After(time.Now()) {
		t.Fatal("server-side WebAuthn timeout was not configured")
	}
	now = store.sessions[ceremonyID].ExpiresAt.Add(-time.Second)
	encoded, _ := json.Marshal(options)
	if !strings.Contains(string(encoded), `"userVerification":"required"`) || !strings.Contains(string(encoded), `"residentKey":"required"`) {
		t.Fatalf("registration options must require UV and resident key: %s", encoded)
	}
	if _, err := store.TakeAdminWebAuthnSession(ceremonyID, "tenant-b", "did:plc:admin", "register", now); err == nil {
		t.Fatal("cross-tenant ceremony must fail")
	}
	if _, err := store.TakeAdminWebAuthnSession(ceremonyID, "tenant-a", "did:plc:admin", "register", now); err != nil {
		t.Fatal(err)
	}
	if _, err := store.TakeAdminWebAuthnSession(ceremonyID, "tenant-a", "did:plc:admin", "register", now); err == nil {
		t.Fatal("ceremony replay must fail")
	}
}
