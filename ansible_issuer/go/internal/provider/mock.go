package provider

// Mock returns a deterministic provider subject derived from email.
// Only used when MOCK_MODE=true; never deployed to production.
type Mock struct{}

func (Mock) ProviderSubject(_, email string) (string, error) {
	return "mock-subject:" + email, nil
}
