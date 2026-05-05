# TW Identity Provider Adapter Contract

This contract defines the issuer-side boundary for a future approved Taiwan
digital identity provider adapter. The current in-memory adapter exists only for
contract tests and local readiness checks.

## Callback Fields

Approved provider callbacks must normalize to these fields before issuance:

- `state`: opaque issuer-generated auth state bound to one pending offer.
- `assertion`: signed provider proof or signed assertion envelope.
- `replay_id`: provider assertion ID, nonce, transaction ID, or equivalent
  single-use callback identifier.
- `provider_subject`: stable provider subject claim extracted from the verified
  assertion. It must not be stored directly.
- `assurance_context`: provider assurance level or certificate context used as
  input to subject commitment derivation.
- `issued_at` and `expires_at`: provider assertion validity window when exposed
  by the upstream provider.

## Validation Rules

The production adapter must reject callbacks when:

- `state` does not match an active auth session.
- The auth session has expired.
- The callback state or `replay_id` was already consumed.
- The signed provider proof is missing or invalid.
- The signed proof is outside its provider validity window.
- The proof audience, redirect URI, or client identifier does not match this
  issuer deployment.

Signature validation must use provider-published trust anchors or partner-issued
credentials. Test-mode assertions such as `signed` are valid only inside unit
tests and local mock mode.

## Local Contract Verifier

The Go issuer includes an HMAC contract verifier for CI and staging-only
provider-shape tests. It validates the same normalized callback fields used by
the production adapter, but it is not a substitute for TW FidO/MOICA trust-anchor
signature verification. Production deployments must configure a provider adapter
that validates partner-issued signatures and audience binding.

## Replay Handling

Each started auth session is single-use. A verified callback consumes both its
`state` and `replay_id`. The production adapter should persist consumed replay
IDs for at least the maximum provider assertion lifetime plus clock skew.

## Subject Derivation

The adapter may return `provider_subject` only inside the issuer process. The
issuer must immediately derive:

```text
HMAC-SHA256(pepper, assurance_context || ":" || provider_subject)
```

Only that commitment may be persisted or compared. Raw national identifiers,
legal names, certificate serial numbers, and provider subject values must not be
written to application databases or logs.

## Retention

Keep only:

- auth session state until expiry or callback consumption;
- consumed replay IDs until replay risk expires;
- derived subject commitments attached to issued credentials;
- audit-safe error counters without raw DID, IP, national ID, or provider
  assertion payloads.

Discard provider assertion payloads after validation unless partner compliance
documentation later requires a short encrypted retention window.
