# Issuer Production Adapter Boundary Design

## Scope

This phase adds only the production adapter boundary and fail-closed wiring for
the Go issuer TW provider flow. It does not integrate a real TW provider API,
SDK, certificate chain, sandbox callback fixture, or trust-anchor validation.

## Design

The issuer already exposes production-shaped TW flow endpoints and verifies
callbacks through `provider.ProofVerifier`. Today the server wires the HMAC
contract verifier directly from `cmd/server/main.go`, which makes staging and
production modes too easy to confuse.

Add a small provider adapter boundary in `internal/provider`:

- `VerifierAdapterMode` identifies `contract` and `production`.
- `VerifierAdapterConfig` carries shared config plus production-only trust
  anchor config fields.
- `NewProofVerifierAdapter` constructs the verifier for a mode.
- `contract` returns the existing HMAC `ContractProofVerifier`.
- `production` fails closed until partner trust-anchor config is present and
  the real verifier is implemented.

Server wiring reads `TW_PROVIDER_ADAPTER_MODE`, defaulting to `contract` in
mock/dev and requiring an explicit mode outside mock mode. Production mode must
never fall back to the contract verifier.

## Fail-Closed Rules

- Missing `TW_PROVIDER_ADAPTER_MODE` outside mock mode is a fatal config error.
- `TW_PROVIDER_ADAPTER_MODE=production` requires production trust-anchor config.
- Even with config present, production adapter construction returns an explicit
  not-implemented error until the approved provider API is available.
- Contract verifier config remains valid only for `contract` mode.

## Testing

Provider tests cover adapter mode selection and production fail-closed behavior.
Server wiring tests cover missing env, contract mode, and production mode
without relying on process exit. Existing API flow tests continue to exercise
only the `ProofVerifier` boundary.
