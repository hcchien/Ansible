# did:elix v1 Existing-Account Migration Product Flow

> Status: implementation specification
> Date: 2026-08-19
> Scope: Elix App, Relay identity registration/anchors, account routing, and
> resolver-visible legacy aliases

## Outcome

Existing accounts remain usable with their legacy `did:elix` until the user
explicitly starts an upgrade. The upgrade creates a schema-v4 v1 identity from
the user's currently active self-custodied key, publishes its genesis anchor,
and submits a dual-signed migration statement. Relay then atomically records
the account transition and routes the existing handle and active write identity
through the v1 DID. The legacy DID remains an immutable,
resolver-verifiable alias for historical signatures and credentials.

New registrations continue to use v1 directly. No background migration is
permitted.

## User Flow

1. Settings shows an `Upgrade did:elix` row only for a legacy identity.
2. The review screen explains that:
   - the public handle is preserved;
   - new writes use the v1 DID;
   - old signed content and third-party credentials keep the legacy DID;
   - the Relay receives public keys, anchors, and signatures, never private key
     or biometric material;
   - a lost legacy key must be recovered before migration.
3. The user checks an informed-consent control and starts the upgrade.
4. Hardware-capable platforms open one short-lived authentication session for
   the explicit operation. All anchor and migration signatures reuse that
   session, while remaining distinct signatures over canonical payloads.
5. The App creates and durably checkpoints a 32-byte CSPRNG genesis nonce and
   derived v1 DID before network writes.
6. The App verifies that the Relay's active legacy anchor matches the local
   active key, then publishes or resumes the schema-v4 v1 genesis anchor.
7. The App signs the canonical migration body with both active identities. A
   same-key transition intentionally produces two proofs with the same
   self-custodied key; a later key rotation remains an independent operation.
8. Relay verifies both complete chains and signatures, then in one database
   transaction records the migration. Alias-aware account and assurance read
   models project the existing handle/trust binding onto v1 without rewriting
   signed history or duplicating a personhood nullifier.
9. Only after Relay returns and the App re-reads the completed record does the
   App switch its canonical local DID. An interrupted attempt is resumable and
   idempotent from its local checkpoint.

## Relay Invariants

- Both active chains exist, validate, and are not frozen.
- The v1 genesis is schema v4 and its immutable commitment derives the claimed
  v1 DID.
- Both active anchors and the legacy account projection have the same handle.
- The legacy account key agrees with the active legacy anchor.
- The migration statement is canonical and signed by both active keys.
- A legacy DID and v1 DID participate in at most one migration.
- Migration evidence commits atomically; handle/account and assurance reads
  switch through that committed evidence.
- A retry of the identical completed migration returns the existing result;
  any different mapping fails closed.
- Historical operations, credentials, anchors, and signatures are not
  rewritten. Resolver `alsoKnownAs`/`equivalentId` establishes continuity.

## Failure And Recovery

- Before Relay completion, the legacy identity remains canonical and usable.
- A local checkpoint records prepared and anchored phases without private key
  material. Relaunching the screen resumes from the last safe phase.
- A Relay timeout after commit is resolved by reading the migration record,
  not by creating a second identity.
- A mismatched Relay key, handle, chain, or migration record blocks the switch
  and leaves the legacy identity unchanged.
- Completed migration is irreversible at the identifier layer. Normal v1 key
  rotation and recovery remain available afterward.

## Data Continuity

- New writes, sync capabilities, recovery events, and push registration use the
  v1 DID after completion.
- Existing recovery-code hashes are DID-domain-separated and therefore cannot
  be copied. The App clearly requires a fresh v1 recovery-code setup while the
  legacy audit trail remains intact.
- Historical signed rows retain their original author DID. Ownership checks
  treat a verified migration pair as the same account where an existing object
  is being managed.
- Wallet credentials are never edited in place. A credential whose subject is
  the legacy DID remains valid through the resolver alias when the verifier
  supports it; otherwise the user requests reissuance.
- Consent-bearing or signature-bearing integrations (for example ActivityPub
  publication consent or web delegations) are not silently rewritten. They are
  re-authorized under v1 when next used.

## Constitution Review

1. **User-controlled identity:** both proofs are produced by the user's active
   self-custodied key; Relay cannot migrate an account by itself.
2. **Data leaving the device:** only public identity material, a public random
   nonce, anchors, timestamps, and detached signatures leave after explicit
   consent.
3. **Minimum disclosure:** the statement contains only the two DIDs and
   timestamp. The handle stays in the already-public account/anchor projection.
4. **Excluded data:** no private key, biometric, legal identity, provider
   assertion, credential payload, or recovery code is sent in the migration.
5. **Trust changes:** no trust tier is raised. An existing binding is moved
   atomically to the equivalent v1 identifier and audited as
   `identity_migrated`.
6. **Personhood binding:** the one existing opaque nullifier binding is
   projected through the verified alias, never duplicated, exposed, or
   regenerated.
7. **Exit/recovery:** migration is optional and resumable; legacy accounts keep
   working until completion, and v1 rotation/recovery remains user-controlled.
8. **External hosts:** the first-party Relay publishes portable dual-signed
   evidence. External hosts may independently verify it and are not trusted as
   migration authorities.
