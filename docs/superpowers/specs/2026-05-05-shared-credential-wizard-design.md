# Shared Credential Wizard Design

## Goal

Refactor credential issuance so Wallet can run issuance inline and
`AddCredentialScreen` can present multiple issuance methods without duplicating
TW provider state.

## Architecture

Add a reusable `CredentialIssuanceWizard` widget. The wizard owns method
selection and embeds method-specific panels:

- `TwProviderCredentialPanel` for production-shaped TW provider issuance.
- `EmailOtpCredentialPanel` for legacy Email OTP issuance.

`TwProviderCredentialScreen` remains as a route wrapper around
`TwProviderCredentialPanel`. `AddCredentialScreen` becomes a route wrapper around
`CredentialIssuanceWizard`. `WalletScreen` embeds the same wizard inline and
reloads credentials after completion.

## Components

### `TwProviderCredentialPanel`

Extract the existing implementation from `TwProviderCredentialScreen` into a
panel widget in `tw_provider_credential_screen.dart`. It keeps the existing
start, launch, poll, issue, store, retry, timeout, and security-error behavior.
It accepts an optional `onCredentialStored` callback so Wallet can reload and
collapse the inline wizard after successful storage.

### `EmailOtpCredentialPanel`

Move the current Email OTP logic from `AddCredentialScreen` into a reusable
panel in `add_credential_screen.dart`. It preserves the existing behavior:
request OTP, issue VC, store in `CredentialWallet`, present VP to relay, and
call `onCredentialAdded`.

### `CredentialIssuanceWizard`

Create `ansible_node/app/lib/screens/credential_issuance_wizard.dart`. It shows
two method buttons:

- `TW 身份驗證`
- `Email OTP / Legacy`

Selecting a method replaces the chooser with the corresponding panel. It also
has a Back to methods action while inside a method panel.

### `WalletScreen`

The Wallet Add credential action no longer pushes a route. It toggles an inline
wizard:

- Empty state shows the Add credential button; clicking reveals the wizard in
  the same screen.
- Credential list screen shows the wizard above the list when expanded.
- Successful TW provider issuance reloads the wallet and collapses the wizard.

## Privacy

The wizard and panels must not store or render TW provider callback fields:
`assertion`, `provider_subject`, raw national ID, legal name, or certificate
serial. Stored wallet data remains limited to VC metadata and the VC payload.

## Tests

Add and update widget tests to verify:

- `TwProviderCredentialScreen` still works as a standalone route wrapper.
- `CredentialIssuanceWizard` shows both flow options.
- Selecting TW embeds the TW provider panel.
- Selecting Email embeds the legacy Email OTP panel.
- `AddCredentialScreen` renders the wizard and can enter both flows.
- `WalletScreen` expands the wizard inline instead of pushing a route.
- Successful inline TW issuance reloads the wallet and hides the wizard.
