# TW Provider App UX Design

## Goal

Build the Flutter app UX for the production-shaped TW provider issuance flow:
users start credential issuance from Wallet, complete provider authorization in
an external browser, return to the app while it polls issuer status, and receive
a stored humanity credential after issuer-side callback verification.

## Scope

This work adds the primary app entry point for TW provider issuance. It does not
remove the legacy Email OTP credential screen, implement provider deep links, or
change relay VP presentation behavior.

## Entry Point

`WalletScreen` becomes the user-facing entry for adding a humanity credential.
It receives the holder DID and testable dependencies from `HomeShell`:

- `holderDid`
- `WalletRepository`
- `VcIssuerClient`
- a URL launcher abstraction

The empty Wallet state and the Wallet app bar expose an Add credential action.
The action pushes a new `TwProviderCredentialScreen`.

## TW Provider Credential Screen

Create `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`.

The screen owns the app-side issuance state machine:

1. `idle`: user enters email.
2. `starting`: app calls `VcIssuerClient.startTwProviderFlow`.
3. `authorizing`: app launches `TwProviderOffer.authorizationUrl`.
4. `polling`: app calls `VcIssuerClient.getTwProviderStatus` every 2 seconds.
5. `issuing`: when status is `verified`, app calls
   `VcIssuerClient.issueTwProviderCredential`.
6. `storing`: app parses and stores the issued credential.
7. `done`: app shows success and returns to Wallet after user confirmation.
8. `error`: app shows a retryable or terminal error state.

Polling stops when:

- status is `verified`;
- the user leaves the screen;
- 2 minutes elapse;
- a terminal security error occurs.

The screen also includes a manual Check again action while polling or after
timeout. This calls status once and resumes the normal verified path if ready.

## URL Launching

Add a small testable launcher boundary instead of calling platform plugins
directly from widgets:

- `ansible_node/app/lib/services/external_url_launcher.dart`
- `ExternalUrlLauncher.open(Uri url) -> Future<bool>`

The production implementation uses `url_launcher`. Widget tests inject a fake
launcher. If opening the provider URL fails, the screen keeps the offer state,
shows an error, and lets the user retry opening the URL or manually check status.

## Credential Storage

When `issueTwProviderCredential` returns VC JSON:

1. Parse it with `VerifiableCredential.fromJson`.
2. Save it to `WalletRepository.saveCredential`.
3. Store the encoded VC payload in the repository payload table.
4. Derive display metadata from the VC only:
   - credential id
   - holder DID
   - issuer DID
   - credential type
   - display name
   - valid until
   - status

The app must not store TW provider `assertion`, `provider_subject`, raw national
ID, legal name, certificate serial, or provider callback bodies.

## Error Handling

Map issuer and app errors into concise user states:

- `provider_not_verified`: keep the current offer and continue waiting.
- `callback_replay`, `state_mismatch`, `invalid_provider_proof`: terminal
  security failure; user must restart.
- `invalid_email`, `invalid_did`, `missing_field`: validation failure; user can
  edit input and retry.
- 5xx or network timeout: retryable service error.
- launch failure: retryable URL launch error; offer is preserved.
- polling timeout: non-terminal waiting state; user can manually check or start
  over.

Error UI must not include raw provider callback fields or raw VC payloads.

## Testing

Add focused widget and unit tests:

- Wallet empty state Add credential opens `TwProviderCredentialScreen`.
- Wallet app bar Add credential opens `TwProviderCredentialScreen`.
- Starting the flow posts DID/email through the fake client and launches the
  provider URL.
- Polling pending then verified triggers issue and saves a wallet credential.
- Launch failure keeps the offer and exposes retry/check actions.
- Polling timeout exposes Check again and Start over actions.
- `provider_not_verified` keeps the flow in waiting state.
- Security errors require restart and do not echo sensitive fields.

Run:

```bash
cd ansible_node/app
flutter test test/tw_provider_credential_screen_test.dart test/wallet_screen_test.dart
flutter test
```

## Out Of Scope

- Provider deep link handling.
- In-app browser embedding.
- Replacing Email OTP legacy flow.
- Relay VP presentation after issuance.
- Production partner-specific provider UI copy.
