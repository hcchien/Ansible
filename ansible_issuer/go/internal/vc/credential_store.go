package vc

// CredentialStore is the issuer's durable duplicate-prevention store. Both the
// file/in-memory *Store and the PostgreSQL *PostgresStore satisfy it, so the
// issuer can run single-instance (file) or horizontally scaled (Postgres) with
// the same code path. The unexported add/2 keeps writes internal to the package.
type CredentialStore interface {
	CheckDuplicate(commitment string) error
	// CheckDuplicateAny reports a duplicate if an active credential exists under
	// ANY of the supplied commitments. It exists so a graceful pepper rotation
	// can dual-check a subject under both the current and previous peppers while
	// still writing new commitments under the primary pepper only.
	CheckDuplicateAny(commitments []string) error
	CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash string) error
	PersonhoodBindingByNationalIDHash(nationalIDHash string) (PersonhoodBinding, bool)
	Status(credentialID string) (CredentialStatus, bool)
	// Revoke marks the credential identified by credentialID as revoked. It
	// returns ErrCredentialNotFound if no such credential exists.
	Revoke(credentialID string) error
	add(record) error
}
