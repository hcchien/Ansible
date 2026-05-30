package commitment

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
)

// Compute returns a deterministic HMAC-SHA256 hex commitment over
// "assuranceContext:subjectValue", keyed by pepper.
// The raw subject value is never stored or returned.
func Compute(pepper, subjectValue, assuranceContext string) string {
	mac := hmac.New(sha256.New, []byte(pepper))
	mac.Write([]byte(assuranceContext + ":" + subjectValue))
	return hex.EncodeToString(mac.Sum(nil))
}
