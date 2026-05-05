package provider

// TwIdentityProvider abstracts TW identity verification.
// Mock returns deterministic subjects for dev/CI. The real adapter will
// integrate with TW FidO / MOICA once partner credentials are available.
type TwIdentityProvider interface {
	// ProviderSubject returns a stable opaque identifier for the verified
	// identity. Callers must pass this through commitment.Compute before
	// persisting or comparing — the raw subject must never be stored.
	ProviderSubject(did, email string) (string, error)
}
