package api_test

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestTWProviderErrorsDoNotEchoSensitiveCallbackFields(t *testing.T) {
	now := time.Date(2026, 5, 5, 12, 0, 0, 0, time.UTC)
	h := newTWHandler(t, now)

	response := call(h, http.MethodPost, "/api/v1/vc/tw/callback", map[string]any{
		"state":             "wrong-state",
		"assertion":         "SIGNED_ASSERTION_PAYLOAD",
		"provider_subject":  "A123456789",
		"legalName":         "Example Name",
		"certificateSerial": "CERT-123",
	})

	body := response.Body.String()
	for _, forbidden := range []string{"SIGNED_ASSERTION_PAYLOAD", "A123456789", "Example Name", "CERT-123"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("response leaked sensitive field %q: %s", forbidden, body)
		}
	}
}
