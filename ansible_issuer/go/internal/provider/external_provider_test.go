package provider_test

import (
	"os"
	"testing"
)

func TestExternalTWProviderSandboxAvailable(t *testing.T) {
	endpoint := os.Getenv("TW_PROVIDER_SANDBOX_URL")
	clientID := os.Getenv("TW_PROVIDER_SANDBOX_CLIENT_ID")
	if endpoint == "" || clientID == "" {
		t.Skip("TW provider sandbox unavailable: missing TW_PROVIDER_SANDBOX_URL or TW_PROVIDER_SANDBOX_CLIENT_ID")
	}

	t.Fatalf("sandbox contract test must be implemented against the approved partner callback fixture before production enablement")
}
