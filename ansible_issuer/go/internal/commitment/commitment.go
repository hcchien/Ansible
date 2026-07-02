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

// Set holds the active commitment peppers: one Primary under which new
// commitments are written, and zero or more Previous peppers retained only so a
// graceful pepper rotation can still recognise an already-issued person.
//
// Without this, rotating SUBJECT_COMMITMENT_PEPPER silently breaks the
// one-person-one-credential invariant: every existing person's commitment is
// computed under the old pepper, so a new pepper produces a fresh value that
// never collides with the stored one and the duplicate check passes for
// everyone. Retaining the old pepper(s) here lets ComputeAll emit both the new
// and legacy commitments so the caller can dual-check on verify while writing
// only the primary value.
type Set struct {
	Primary  string
	Previous []string
}

// NewSet builds a pepper Set from a primary pepper and an ordered list of
// previous peppers. Empty entries are dropped, and any previous pepper equal to
// the primary is dropped so ComputeAll does not emit duplicate commitments.
func NewSet(primary string, previous []string) Set {
	cleaned := make([]string, 0, len(previous))
	seen := map[string]struct{}{primary: {}}
	for _, p := range previous {
		if p == "" {
			continue
		}
		if _, dup := seen[p]; dup {
			continue
		}
		seen[p] = struct{}{}
		cleaned = append(cleaned, p)
	}
	return Set{Primary: primary, Previous: cleaned}
}

// Primary returns the commitment written for newly issued credentials — always
// computed under the primary pepper.
func (s Set) PrimaryCommitment(subjectValue, assuranceContext string) string {
	return Compute(s.Primary, subjectValue, assuranceContext)
}

// ComputeAll returns the commitment under the primary pepper first, followed by
// the commitment under each previous pepper. The duplicate check should test
// every returned value so a person enrolled under an old pepper is still
// recognised after rotation; the caller persists only the primary (element 0).
func (s Set) ComputeAll(subjectValue, assuranceContext string) []string {
	out := make([]string, 0, 1+len(s.Previous))
	out = append(out, Compute(s.Primary, subjectValue, assuranceContext))
	for _, p := range s.Previous {
		out = append(out, Compute(p, subjectValue, assuranceContext))
	}
	return out
}
