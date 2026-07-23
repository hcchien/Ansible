# TW person-binding circuit

This Noir package extends the pinned upstream
`zkpassport/circuits@d3a75acb8529e82c61be136a402553daec259257`.

Overlay this directory at
`src/noir/bin/tw-person-binding/standard`, add that path to the upstream
workspace, then compile with Noir `1.0.0-beta.22` and Barretenberg `5.0.0`.

The circuit reads the Taiwan national identifier from TD3 MRZ optional-data
positions 72–81, validates its syntax/checksum, and emits only a
domain-separated SHA-256 binding input, packed with the same 31-byte field
encoding used by the pinned upstream circuits. It preserves the upstream
integrity-to-disclosure commitment and scoped-nullifier chain, so the value is
cryptographically tied to authenticated DG1.

The emitted field is an intermediate verifier value. The Issuer must wrap it
with `SUBJECT_COMMITMENT_PEPPER` in the `tw_national_id_v1` namespace before
durable storage. Neither the
field nor the raw identifier belongs in a VC, log, Relay payload, or
federation payload.
