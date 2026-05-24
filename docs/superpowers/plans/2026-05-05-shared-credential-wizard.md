# Shared Credential Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor credential issuance into a shared multi-flow wizard used by both AddCredentialScreen and Wallet inline issuance.

**Architecture:** Extract TW provider orchestration into `TwProviderCredentialPanel`, extract Email OTP legacy orchestration into `EmailOtpCredentialPanel`, and create `CredentialIssuanceWizard` to select and host either panel. `TwProviderCredentialScreen` and `AddCredentialScreen` become route wrappers while `WalletScreen` embeds the wizard inline.

**Tech Stack:** Flutter widgets, existing `VcIssuerClient`, `ExternalUrlLauncher`, `WalletRepository`, `CredentialWallet`, `AtProtoClient`, `VpBuilder`, Flutter widget tests.

---

## Task 1: Extract TW Provider Panel

**Files:**
- Modify: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
- Modify: `ansible_node/app/test/tw_provider_credential_screen_test.dart`

- [ ] Write a failing test that renders `TwProviderCredentialPanel` directly and verifies start/launch.
- [ ] Refactor existing `TwProviderCredentialScreen` body into `TwProviderCredentialPanel`.
- [ ] Add `VoidCallback? onCredentialStored` and call it after successful wallet save.
- [ ] Keep `TwProviderCredentialScreen` as `Scaffold(appBar, body: TwProviderCredentialPanel(...))`.
- [ ] Run `flutter test test/tw_provider_credential_screen_test.dart`.
- [ ] Commit `feat: extract TW provider credential panel`.

## Task 2: Add Credential Issuance Wizard

**Files:**
- Create: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Create: `ansible_node/app/test/credential_issuance_wizard_test.dart`

- [ ] Write failing tests that the wizard shows `TW 身份驗證` and `Email OTP / Legacy`.
- [ ] Write failing tests that tapping TW shows `開始驗證`.
- [ ] Write failing tests that tapping Email shows `Email 聯絡方式驗證`.
- [ ] Implement `CredentialIssuanceWizard` with method selection and method panels.
- [ ] For this task, use a placeholder `EmailOtpCredentialPanel` shell with title `Email 聯絡方式驗證`; Task 3 replaces it with real legacy behavior.
- [ ] Run `flutter test test/credential_issuance_wizard_test.dart`.
- [ ] Commit `feat: add credential issuance wizard`.

## Task 3: Refactor AddCredentialScreen Into Wizard Wrapper

**Files:**
- Modify: `ansible_node/app/lib/screens/add_credential_screen.dart`
- Modify: `ansible_node/app/lib/screens/credential_issuance_wizard.dart`
- Create: `ansible_node/app/test/add_credential_screen_test.dart`

- [ ] Write failing tests that `AddCredentialScreen` renders both wizard options.
- [ ] Write failing tests that choosing Email starts the existing OTP flow and shows `發送驗證碼`.
- [ ] Extract current AddCredentialScreen stateful implementation into `EmailOtpCredentialPanel`.
- [ ] Make `AddCredentialScreen` render `CredentialIssuanceWizard` and pass Email dependencies into it.
- [ ] Replace the wizard placeholder Email panel with `EmailOtpCredentialPanel`.
- [ ] Run `flutter test test/add_credential_screen_test.dart test/credential_issuance_wizard_test.dart`.
- [ ] Commit `feat: make AddCredentialScreen a multi-flow wizard`.

## Task 4: Embed Wizard Inline In WalletScreen

**Files:**
- Modify: `ansible_node/app/lib/screens/wallet_screen.dart`
- Modify: `ansible_node/app/test/wallet_screen_test.dart`

- [ ] Update Wallet tests to expect Add credential expands `CredentialIssuanceWizard` inline instead of navigating to `TwProviderCredentialScreen`.
- [ ] Add a Wallet test that successful inline TW issuance reloads credentials and hides the wizard.
- [ ] Implement `_showWizard` state in `WalletScreen`.
- [ ] Render `CredentialIssuanceWizard` inline in empty and list states.
- [ ] On wizard completion, reload wallet and collapse the wizard.
- [ ] Run `flutter test test/wallet_screen_test.dart`.
- [ ] Commit `feat: embed credential wizard in wallet`.

## Task 5: Verification

**Files:**
- Modify as needed based on verification.

- [ ] Run `dart format` on changed Dart files.
- [ ] Run `flutter test` in `ansible_node/app`.
- [ ] Run privacy scan:

```bash
rg -n "nationalId|legalName|birthDate|certificateSerial|provider_subject|assertion" ansible_node/app ansible_core/vc
```

Expected: no new app screen or wallet code stores or renders provider callback fields.

- [ ] Commit verification fixes if any.
