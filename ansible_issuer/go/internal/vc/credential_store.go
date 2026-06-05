package vc

// CredentialStore is the issuer's durable duplicate-prevention store. Both the
// file/in-memory *Store and the PostgreSQL *PostgresStore satisfy it, so the
// issuer can run single-instance (file) or horizontally scaled (Postgres) with
// the same code path. The unexported add/2 keeps writes internal to the package.
type CredentialStore interface {
	CheckDuplicate(commitment string) error
	CheckDuplicatePersonhoodBinding(nationalIDHash, passportNumberHash string) error
	PersonhoodBindingByNationalIDHash(nationalIDHash string) (PersonhoodBinding, bool)
	Status(credentialID string) (CredentialStatus, bool)
	add(record) error
}
