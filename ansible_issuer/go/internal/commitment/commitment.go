package commitment

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
)

// Compute returns a deterministic HMAC-SHA256 hex commitment over
// "assuranceContext:providerSubject", keyed by pepper.
// The raw provider subject is never stored or returned.
func Compute(pepper, providerSubject, assuranceContext string) string {
	mac := hmac.New(sha256.New, []byte(pepper))
	mac.Write([]byte(assuranceContext + ":" + providerSubject))
	return hex.EncodeToString(mac.Sum(nil))
}
