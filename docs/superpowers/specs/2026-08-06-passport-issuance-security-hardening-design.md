# Passport issuance security hardening

## Goal

Passport NFC issuance must reject a valid passport proof when it is submitted
by a device that does not control the DID embedded in that proof.  It must also
make proof substitution, replay, and verifier-response substitution detectable
without sending passport or MRZ data to Issuer or Relay.

## Constitution Review

This change touches verification, credentials, identity, and Relay discovery.
It preserves the engineering constitution's local-first and minimization
requirements: raw NFC/passport data stays in the Wallet's ephemeral local
prover path; Relay never receives passport data or a personhood commitment;
Issuer persists only its peppered duplicate-prevention commitment and issued
credential status.  Relay is used only to discover a DID verification key, and
Issuer verifies the holder signature itself.  It is not a source of identity
or credential authority.  The existing compliance review's warning that the
unassisted lost-DID transfer remains future work is unchanged.

## Protocol: `elix-passport-issuance-v1`

1. Wallet requests an unpredictable, single-use challenge for its DID.
2. Wallet creates the ZKPassport proof locally.  The proof binds `challenge_id`,
   `challenge_nonce`, DID, Issuer URL, and scope through its public inputs.
3. Wallet computes `SHA-256(zkp_proof)` and signs this canonical JSON with the
   active DID identity key:

   ```json
   {"protocol":"elix-passport-issuance-v1","action":"issue","did":"…","challenge_id":"…","challenge_nonce":"…","issuer":"…","scope":"…","nationality":"TWN","zkp_proof_sha256":"…","zkp_circuit_version":"0.20.0","verification_key_hash":"…"}
   ```

4. Issuer resolves the DID public key from the configured Relay endpoint and
   verifies the detached signature locally (`ed25519` or `p256-sha256`).
5. Issuer invokes the private ZK verifier using a Cloud Run workload identity.
   The verifier checks the ZK binding and returns only the approved claim and
   opaque duplicate-prevention input.  It cannot issue a credential.
6. Issuer atomically consumes the challenge only after all checks pass, then
   applies duplicate prevention and issues the credential.

## Operational rules

- `PASSPORT_VERIFIER_URL` may not enable issuance unless
  `PASSPORT_DID_RESOLVER_URL` is configured. Startup fails closed otherwise.
- The verifier must remain private (`--no-allow-unauthenticated`) and grant
  `run.invoker` solely to the Issuer workload service account.
- The Issuer must never log HTTP bodies, ZK proofs, passport hashes, nonce, or
  signatures. Request errors use stable reason codes only.
- Client requests no longer transmit local `national_id_hash` or
  `passport_number_hash`; the verifier derives the duplicate-prevention input
  from the verified proof itself.
- Passport issuance remains disabled in production until the deployed issuer,
  private verifier IAM policy, and current TestFlight app have passed the
  device NFC test suite.

## Required test cases

- valid signature and current DID key succeeds;
- absent/invalid signature is rejected before ZK verification;
- any change to DID, nonce, issuer, scope, nationality, circuit metadata, or
  proof digest invalidates the signature;
- a proof cannot be replayed and cannot use another DID's challenge;
- resolver response for a different DID or unsupported key algorithm fails;
- the verifier endpoint rejects unauthenticated calls and Issuer rejects a
  verifier response whose claim/binding does not match the challenge.
