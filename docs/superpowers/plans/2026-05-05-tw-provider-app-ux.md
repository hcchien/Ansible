# TW Provider App UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Flutter Wallet-first UX for TW provider credential issuance.

**Architecture:** Add a testable URL launcher boundary and a dedicated `TwProviderCredentialScreen` that orchestrates start, external authorization, polling, issue, and wallet persistence. Wire `WalletScreen` to open the new flow from both empty state and app bar while preserving the legacy Email OTP screen.

**Tech Stack:** Flutter, `url_launcher`, `ansible_store` `WalletRepository`, `ansible_vc` `VerifiableCredential`, existing `VcIssuerClient` TW provider methods, Flutter widget tests with fake clients and fake launchers.

---

## File Structure

- Create: `ansible_node/app/lib/services/external_url_launcher.dart`
  - Defines `ExternalUrlLauncher` and production `UrlLauncherExternalUrlLauncher`.
- Modify: `ansible_node/app/pubspec.yaml`
  - Adds `url_launcher`.
- Create: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
  - Dedicated TW provider issuance state machine and UI.
- Modify: `ansible_node/app/lib/screens/wallet_screen.dart`
  - Adds holder DID/client/launcher dependencies and Add credential navigation.
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
  - Passes the anchored DID into `WalletScreen`.
- Create: `ansible_node/app/test/tw_provider_credential_screen_test.dart`
  - Tests start/launch, polling, issue/store, and error states.
- Modify: `ansible_node/app/test/wallet_screen_test.dart`
  - Tests Add credential navigation from Wallet.

## Task 1: URL Launcher Boundary

**Files:**
- Create: `ansible_node/app/lib/services/external_url_launcher.dart`
- Modify: `ansible_node/app/pubspec.yaml`

- [ ] **Step 1: Add dependency**

Run:

```bash
cd ansible_node/app
flutter pub add url_launcher
```

Expected: `pubspec.yaml` gains `url_launcher` and `pubspec.lock` updates.

- [ ] **Step 2: Create launcher boundary**

Create `lib/services/external_url_launcher.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

abstract class ExternalUrlLauncher {
  Future<bool> open(Uri url);
}

class UrlLauncherExternalUrlLauncher implements ExternalUrlLauncher {
  const UrlLauncherExternalUrlLauncher();

  @override
  Future<bool> open(Uri url) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
```

- [ ] **Step 3: Format and commit**

Run:

```bash
cd ansible_node/app
dart format lib/services/external_url_launcher.dart
git add ansible_node/app/pubspec.yaml ansible_node/app/pubspec.lock ansible_node/app/lib/services/external_url_launcher.dart
git commit -m "feat: add external URL launcher boundary"
```

## Task 2: Wallet Add Credential Navigation

**Files:**
- Modify: `ansible_node/app/lib/screens/wallet_screen.dart`
- Modify: `ansible_node/app/lib/screens/home_shell.dart`
- Modify: `ansible_node/app/test/wallet_screen_test.dart`
- Create: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`

- [ ] **Step 1: Write failing Wallet navigation tests**

Add to `test/wallet_screen_test.dart`:

```dart
testWidgets('empty wallet add credential opens TW provider flow', (tester) async {
  final repo = InMemoryWalletRepository();
  await tester.pumpWidget(MaterialApp(
    home: WalletScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      repository: repo,
    ),
  ));

  await tester.tap(find.text('Add credential'));
  await tester.pumpAndSettle();

  expect(find.text('TW 身份驗證'), findsOneWidget);
});

testWidgets('wallet app bar add credential opens TW provider flow', (tester) async {
  final repo = InMemoryWalletRepository.withCredentials([
    WalletCredential(
      credentialId: 'urn:uuid:test-humanity',
      issuerDid: 'did:web:issuer.elix.cool',
      holderDid: 'did:plc:abcdefghijklmnop',
      credentialType: 'TrisAuraHumanityCredential',
      status: WalletCredentialStatus.active,
      validFrom: DateTime.utc(2026, 5, 5),
      validUntil: DateTime.utc(2026, 8, 3),
      displayName: 'Verified Human',
      createdAt: DateTime.utc(2026, 5, 5),
      updatedAt: DateTime.utc(2026, 5, 5),
    ),
  ]);
  await tester.pumpWidget(MaterialApp(
    home: WalletScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      repository: repo,
    ),
  ));

  await tester.tap(find.byTooltip('Add credential'));
  await tester.pumpAndSettle();

  expect(find.text('TW 身份驗證'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd ansible_node/app
flutter test test/wallet_screen_test.dart
```

Expected: FAIL because `WalletScreen` has no `holderDid` parameter and no TW provider screen.

- [ ] **Step 3: Add minimal TW provider screen shell**

Create `lib/screens/tw_provider_credential_screen.dart`:

```dart
import 'package:flutter/material.dart';

class TwProviderCredentialScreen extends StatelessWidget {
  const TwProviderCredentialScreen({super.key, required this.holderDid});

  final String holderDid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TW 身份驗證')),
      body: const Center(child: Text('TW 身份驗證')),
    );
  }
}
```

- [ ] **Step 4: Wire Wallet navigation**

Modify `WalletScreen` constructor to require `holderDid`, add an app bar Add action, and pass `onAddCredential` into `_EmptyWalletState`.

Navigation body:

```dart
Future<void> _openAddCredential() async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TwProviderCredentialScreen(holderDid: widget.holderDid),
    ),
  );
  await _reload();
}
```

Modify `home_shell.dart` Wallet route:

```dart
WalletScreen(
  holderDid: anchoredDid,
  repository: DriftWalletRepository(db),
)
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
cd ansible_node/app
dart format lib/screens/wallet_screen.dart lib/screens/home_shell.dart lib/screens/tw_provider_credential_screen.dart test/wallet_screen_test.dart
flutter test test/wallet_screen_test.dart
git add ansible_node/app/lib/screens/wallet_screen.dart ansible_node/app/lib/screens/home_shell.dart ansible_node/app/lib/screens/tw_provider_credential_screen.dart ansible_node/app/test/wallet_screen_test.dart
git commit -m "feat: open TW provider flow from wallet"
```

## Task 3: Start Flow And Launch Provider URL

**Files:**
- Modify: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
- Create: `ansible_node/app/test/tw_provider_credential_screen_test.dart`

- [ ] **Step 1: Write failing start/launch test**

Create `test/tw_provider_credential_screen_test.dart` with fake client and launcher classes. The first test:

```dart
testWidgets('starts TW provider flow and launches authorization URL', (tester) async {
  final client = FakeTwIssuerClient(
    offer: TwProviderOffer(
      offerId: 'offer-1',
      state: 'state-1',
      authorizationUrl: Uri.parse('https://provider.example/authorize?state=state-1'),
      expiresAt: DateTime.utc(2026, 5, 5, 12, 5),
    ),
  );
  final launcher = FakeExternalUrlLauncher();

  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: client,
      urlLauncher: launcher,
      walletRepository: InMemoryWalletRepository(),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump();

  expect(client.startedWithEmail, 'alice@example.com');
  expect(launcher.opened.single.toString(), contains('state-1'));
  expect(find.text('等待 provider 驗證完成'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd ansible_node/app
flutter test test/tw_provider_credential_screen_test.dart
```

Expected: FAIL because `TwProviderCredentialScreen` does not accept dependencies or implement start.

- [ ] **Step 3: Implement start and launch**

Update `TwProviderCredentialScreen` to accept:

```dart
final String holderDid;
final VcIssuerClient? vcIssuerClient;
final ExternalUrlLauncher? urlLauncher;
final WalletRepository? walletRepository;
final Duration pollInterval;
final Duration pollTimeout;
```

Add `_Phase.idle`, `_Phase.starting`, `_Phase.polling`, `_Phase.error`, email controller, and `_startFlow()` that validates email, calls `startTwProviderFlow`, calls `urlLauncher.open`, stores current offer, and displays `等待 provider 驗證完成`.

- [ ] **Step 4: Run test and commit**

Run:

```bash
cd ansible_node/app
dart format lib/screens/tw_provider_credential_screen.dart test/tw_provider_credential_screen_test.dart
flutter test test/tw_provider_credential_screen_test.dart
git add ansible_node/app/lib/screens/tw_provider_credential_screen.dart ansible_node/app/test/tw_provider_credential_screen_test.dart
git commit -m "feat: start TW provider app flow"
```

## Task 4: Poll Verified, Issue, And Store

**Files:**
- Modify: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
- Modify: `ansible_node/app/test/tw_provider_credential_screen_test.dart`

- [ ] **Step 1: Write failing poll/issue/store test**

Add test:

```dart
testWidgets('polls until verified then issues and stores credential', (tester) async {
  final repo = InMemoryWalletRepository();
  final client = FakeTwIssuerClient(
    offer: twOfferFixture(),
    statuses: ['pending', 'verified'],
    vc: humanityVcFixture(),
  );

  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: client,
      urlLauncher: FakeExternalUrlLauncher(),
      walletRepository: repo,
      pollInterval: const Duration(milliseconds: 10),
      pollTimeout: const Duration(seconds: 1),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();

  final credentials = await repo.listCredentials();
  expect(credentials.single.credentialType, 'TrisAuraHumanityCredential');
  expect(credentials.single.holderDid, 'did:plc:abcdefghijklmnop');
  expect(await repo.getEncryptedPayload(credentials.single.credentialId), isNotNull);
  expect(find.text('憑證已加入 Wallet'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd ansible_node/app
flutter test test/tw_provider_credential_screen_test.dart
```

Expected: FAIL because polling, issue, and repository save are not implemented.

- [ ] **Step 3: Implement polling and storage**

Add timer-based polling:

```dart
Timer? _pollTimer;
DateTime? _pollStartedAt;
```

On verified, call `issueTwProviderCredential`, parse `VerifiableCredential`, then call:

```dart
await _walletRepository.saveCredential(
  metadata: WalletCredential(
    credentialId: vc.id,
    issuerDid: vc.issuer,
    holderDid: vc.holderDid ?? widget.holderDid,
    credentialType: vc.type.last,
    status: WalletCredentialStatus.active,
    validFrom: DateTime.parse(vc.issuanceDate),
    validUntil: DateTime.parse(vc.expirationDate!),
    displayName: 'Verified Human',
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
  ),
  encryptedPayload: jsonEncode(vc.toJson()),
  encryptionVersion: 'plain-json-v1',
);
```

- [ ] **Step 4: Run test and commit**

Run:

```bash
cd ansible_node/app
dart format lib/screens/tw_provider_credential_screen.dart test/tw_provider_credential_screen_test.dart
flutter test test/tw_provider_credential_screen_test.dart
git add ansible_node/app/lib/screens/tw_provider_credential_screen.dart ansible_node/app/test/tw_provider_credential_screen_test.dart
git commit -m "feat: issue and store TW provider credential"
```

## Task 5: Error States And Full Verification

**Files:**
- Modify: `ansible_node/app/lib/screens/tw_provider_credential_screen.dart`
- Modify: `ansible_node/app/test/tw_provider_credential_screen_test.dart`
- Modify: `ansible_node/app/test/wallet_screen_test.dart`

- [ ] **Step 1: Add failing error tests**

Add these tests to `test/tw_provider_credential_screen_test.dart`:

```dart
testWidgets('launch failure keeps offer and shows retry actions', (tester) async {
  final launcher = FakeExternalUrlLauncher(shouldOpen: false);
  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: FakeTwIssuerClient(offer: twOfferFixture()),
      urlLauncher: launcher,
      walletRepository: InMemoryWalletRepository(),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump();

  expect(find.text('開啟驗證頁失敗'), findsOneWidget);
  expect(find.text('重新開啟驗證頁'), findsOneWidget);
  expect(find.text('重新檢查'), findsOneWidget);
});

testWidgets('poll timeout shows check again and start over actions', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: FakeTwIssuerClient(
        offer: twOfferFixture(),
        statuses: ['pending', 'pending', 'pending'],
      ),
      urlLauncher: FakeExternalUrlLauncher(),
      walletRepository: InMemoryWalletRepository(),
      pollInterval: const Duration(milliseconds: 10),
      pollTimeout: const Duration(milliseconds: 20),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump(const Duration(milliseconds: 40));

  expect(find.text('尚未收到驗證結果'), findsOneWidget);
  expect(find.text('重新檢查'), findsOneWidget);
  expect(find.text('重新開始'), findsOneWidget);
});

testWidgets('provider_not_verified keeps waiting state', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: FakeTwIssuerClient(
        offer: twOfferFixture(),
        statuses: ['verified'],
        issueError: const VcIssuerException(
          statusCode: 409,
          error: 'provider_not_verified',
        ),
      ),
      urlLauncher: FakeExternalUrlLauncher(),
      walletRepository: InMemoryWalletRepository(),
      pollInterval: const Duration(milliseconds: 10),
      pollTimeout: const Duration(seconds: 1),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump(const Duration(milliseconds: 50));

  expect(find.text('等待 provider 驗證完成'), findsOneWidget);
});

testWidgets('security errors require restart without echoing sensitive fields', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: TwProviderCredentialScreen(
      holderDid: 'did:plc:abcdefghijklmnop',
      vcIssuerClient: FakeTwIssuerClient(
        offer: twOfferFixture(),
        statuses: ['verified'],
        issueError: const VcIssuerException(
          statusCode: 401,
          error: 'invalid_provider_proof',
        ),
      ),
      urlLauncher: FakeExternalUrlLauncher(),
      walletRepository: InMemoryWalletRepository(),
      pollInterval: const Duration(milliseconds: 10),
      pollTimeout: const Duration(seconds: 1),
    ),
  ));

  await tester.enterText(find.byType(TextField), 'alice@example.com');
  await tester.tap(find.text('開始驗證'));
  await tester.pump(const Duration(milliseconds: 50));

  expect(find.text('驗證安全檢查失敗，請重新開始。'), findsOneWidget);
  expect(find.text('重新開始'), findsOneWidget);
  expect(find.textContaining('SIGNED_ASSERTION_PAYLOAD'), findsNothing);
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd ansible_node/app
flutter test test/tw_provider_credential_screen_test.dart
```

Expected: FAIL because error actions and mappings are incomplete.

- [ ] **Step 3: Implement error mappings and actions**

Implement:

- retry launch uses stored `_offer.authorizationUrl`;
- check again calls status once;
- timeout cancels timer and shows non-terminal timeout state;
- `provider_not_verified` keeps polling/waiting;
- `callback_replay`, `state_mismatch`, `invalid_provider_proof` show terminal restart state;
- all error messages are fixed strings that do not include server detail payloads.

- [ ] **Step 4: Run targeted and full tests**

Run:

```bash
cd ansible_node/app
dart format lib/screens/tw_provider_credential_screen.dart lib/screens/wallet_screen.dart lib/screens/home_shell.dart test/tw_provider_credential_screen_test.dart test/wallet_screen_test.dart
flutter test test/tw_provider_credential_screen_test.dart test/wallet_screen_test.dart
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Privacy scan**

Run:

```bash
rg -n "nationalId|legalName|birthDate|certificateSerial|provider_subject|assertion" ansible_node/app ansible_core/vc
```

Expected: raw identity fields appear only in VC guard tests/models and not in the new TW provider app screen or wallet persistence code.

- [ ] **Step 6: Commit**

Run:

```bash
git add ansible_node/app/lib/screens/tw_provider_credential_screen.dart ansible_node/app/lib/screens/wallet_screen.dart ansible_node/app/lib/screens/home_shell.dart ansible_node/app/test/tw_provider_credential_screen_test.dart ansible_node/app/test/wallet_screen_test.dart
git commit -m "test: cover TW provider app UX errors"
```
