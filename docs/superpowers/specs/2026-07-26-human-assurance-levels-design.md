# Human Assurance Levels

> Date: 2026-07-26
> Status: Implemented design
> Scope: Issuer humanity credentials, Relay reputation, App verification

## Decision

Human verification is no longer represented as one undifferentiated trust
score. First-party systems represent three orthogonal dimensions:

1. `identity_control`: `did_key`, operation-scoped `passkey_uv`, or
   `hardware_bound` when independently established.
2. `human_evidence`: `none`, `liveness`, `natural_person`, or
   `legacy_verified`.
3. `uniqueness`: `unknown`, `limited`, or `strong`.

A passkey may provide stronger account control than video liveness while
providing no human evidence. Video may provide liveness evidence while
providing no durable account control or strong uniqueness. The dimensions MUST
NOT be collapsed into a statement that one method is globally “more trusted.”

`reputation_tier` remains a compatibility projection for existing APIs:

- no accepted human evidence → `basic`
- natural-person evidence with limited/unknown uniqueness →
  `humanity_limited`
- legacy humanity VC → `verified_human`
- natural-person evidence with strong uniqueness → `unique_human`

This projection is useful for existing posting/rate-limit gates, but is not the
canonical assurance model. `dns_verified` remains a legacy reputation signal
and does not provide human assurance.

New `TrisAuraHumanityCredential` subjects carry only the minimum portable
assurance claims:

- `humanAssurance`: `verified`
- `uniquenessAssurance`: `strong`, `limited`, or `unknown`
- `verificationMethodClass`: `government_document`, `government_eid`,
  `liveness`, or `community`

The exact method may remain during the compatibility period in the existing
`assuranceMethod` field, but authorization MUST use the assurance claims rather
than infer strength from country or document name.

## Compatibility

- A legacy, valid `TrisAuraHumanityCredential` without the new claims maps to
  `verified_human`.
- New passport NFC and Taiwan natural-person credentials map to
  `unique_human` because the Issuer already enforces an active keyed,
  non-reversible duplicate-prevention commitment.
- A future video-liveness credential without strong uniqueness maps to
  `humanity_limited`.
- Gates requiring `verified_human` accept `unique_human`.
- Gates requiring `unique_human` reject legacy and limited credentials.

No phone-control or email credential maps to a human tier.

## Product Use

Authorization declares the dimensions it needs. Login or signing decisions
inspect `identity_control`; ordinary anti-bot surfaces may accept liveness with
rate limits; governance and one-person-one-vote require `uniqueness=strong`.

The initial Fediverse gate remains `verified_human`, so this change does not
silently broaden federation access to future liveness-only credentials.

## Constitution Review

1. The holder DID and issuer-signed VC remain the user-controlled evidence.
2. Only explicitly presented assurance claims leave the Wallet.
3. Verifiers receive assurance strength, not legal identity.
4. Raw documents, government identifiers, provider subjects, biometric
   material, and duplicate-prevention commitments are excluded.
5. Tier changes remain derived from verified evidence and have stable labels.
6. Strong uniqueness continues to require an issuer-local keyed,
   domain-separated, irreversible commitment.
7. `basic` and limited-assurance paths remain available; credentials retain
   expiry and revocation semantics.
8. External issuer trust continues to be governed by the issuer registry.
