import 'dart:async';
import 'dart:io';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:app_links/app_links.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config/app_environment.dart';
import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_shell.dart';
import 'screens/identity_backup_screen.dart'; // Backup blob creation (nag-once)
import 'screens/onboarding_backup_step_screen.dart'; // Post-registration backup + initial anchor
import 'screens/onboarding_intro_screen.dart';
import 'screens/passkeys_registration_screen.dart'; // V2.0: Passkeys registration
import 'screens/posts_view_screen.dart';
import 'screens/recovery_wizard_screen.dart'; // Restore-from-backup recovery
import 'screens/threads_list_screen.dart';
import 'screens/web_session_approval_screen.dart';
import 'services/identity_anchor_service.dart';
import 'services/recovery_readiness_store.dart';
import 'services/relay_anchor_client.dart';
import 'services/secure_device_key_store.dart';
import 'services/app_locale_controller.dart';
import 'services/backup_policy_service.dart';
import 'services/canonical_identity_store.dart';
import 'services/elix_content_link.dart';
import 'services/elix_content_router.dart';
import 'services/reading_preferences_controller.dart';
import 'services/relay_identity_client.dart';
import 'services/web_session_approval_client.dart';
import 'services/web_session_grant_service.dart';
import 'theme/ansible_design.dart';

final ElixThemeController themeController = ElixThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppEnvironment.validateRuntimeReadiness(
      isReleaseBuild: kReleaseMode,
      usesDevelopmentRustBridge: !AppEnvironment.hasRealRustBridge,
    );

    // Initialise the Rust native library (Ed25519, did:key, signing).
    // initRustBridge() picks the right loader per platform: iOS resolves the
    // statically-linked symbols from the process, others open the dynamic lib.
    await initRustBridge();
    await _resetLocalIdentityIfRequested();

    // Load persisted theme before the first frame.
    await themeController.load();

    // Initialise local SQLite store (Drift schema v7).
    // No username/password — identity is DID-based.
    final storagePaths = await BackupPolicyService().prepareStorage();
    final db = await _openAppDatabase(storagePaths: storagePaths);

    runApp(MyApp(db: db, webSessionLinks: AppLinks().uriLinkStream));
  } catch (error, stack) {
    // A failure before runApp() otherwise shows a blank screen with no clue.
    // Surface it on-device so startup problems are diagnosable.
    runApp(_BootErrorApp(error: error, stack: stack));
  }
}

/// Minimal app shown when startup fails before the real UI can mount.
class _BootErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace stack;
  const _BootErrorApp({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Startup failed',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '$error',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<AppDatabase> _openAppDatabase({BackupPolicyPaths? storagePaths}) async {
  final dbFolder =
      storagePaths?.canonicalDirectory ??
      await getApplicationSupportDirectory();
  await dbFolder.create(recursive: true);
  final file = File(p.join(dbFolder.path, 'ansible.db'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}

Future<void> _resetLocalIdentityIfRequested() async {
  const reset = AppEnvironment.resetLocalIdentityOnStart;
  if (!reset) return;

  await const SecureCanonicalIdentityStore().delete();
  await DidPlcManagerImpl().deleteDid();
  await PasskeysManagerImpl().delete();
  await DidManagerImpl().delete();
}

class MyApp extends StatefulWidget {
  final AppDatabase db;
  final DidManager? didManager;
  final DidPlcManager? didPlcManager;
  final CanonicalIdentityStore? canonicalIdentityStore;
  final DidSigner? didSigner;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final Stream<Uri>? webSessionLinks;
  // ignore: unused_field — kept for V1 test-injection compatibility; V2.0 uses AtProtoClient
  final RelayIdentityClient? relayIdentityClient;

  /// Board shown on launch (forwarded to [HomeShell]). Defaults to the Timeline.
  final HomeBoard initialBoard;

  const MyApp({
    super.key,
    required this.db,
    this.didManager,
    this.didPlcManager,
    this.canonicalIdentityStore,
    this.didSigner,
    this.localeController,
    this.readingPreferencesController,
    this.webSessionLinks,
    this.relayIdentityClient,
    this.initialBoard = HomeBoard.timeline,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Identity state: null = not anchored, non-null = DID string
  String? _anchoredDid;
  String? _anchoredPublicKeyHex;
  bool _loadingIdentity = true;
  // First-run: show the onboarding intro (Welcome/Promise) before the passkey
  // ("first key") screen.
  bool _introDone = false;
  late final DidManager _didManager;
  late final DidPlcManager _didPlcManager;
  late final CanonicalIdentityStore _canonicalIdentityStore;
  late final AppLocaleController _localeController;
  late final bool _ownsLocaleController;
  late final ReadingPreferencesController _readingPreferencesController;
  late final bool _ownsReadingPreferencesController;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Uri>? _webSessionLinkSubscription;

  @override
  void initState() {
    super.initState();
    _didManager = widget.didManager ?? DidManagerImpl();
    _didPlcManager = widget.didPlcManager ?? DidPlcManagerImpl();
    _canonicalIdentityStore =
        widget.canonicalIdentityStore ?? const SecureCanonicalIdentityStore();
    _localeController = widget.localeController ?? AppLocaleController();
    _ownsLocaleController = widget.localeController == null;
    _readingPreferencesController =
        widget.readingPreferencesController ?? ReadingPreferencesController();
    _ownsReadingPreferencesController =
        widget.readingPreferencesController == null;
    _localeController.load();
    _readingPreferencesController.load();
    _loadPersistedIdentity();
    _webSessionLinkSubscription = widget.webSessionLinks?.listen(
      _handleWebSessionLink,
    );
  }

  @override
  void dispose() {
    if (_ownsLocaleController) {
      _localeController.dispose();
    }
    if (_ownsReadingPreferencesController) {
      _readingPreferencesController.dispose();
    }
    _webSessionLinkSubscription?.cancel();
    super.dispose();
  }

  void _handleWebSessionLink(Uri uri) {
    if (_isMobileMoicaCallbackLink(uri)) {
      return;
    }

    // Outbound sharing loop (PM review finding #2): a tapped Elix board/thread
    // link opens the app and routes to that content.
    final contentRef = ElixContentLink.parse(
      uri,
      allowLocalHttp: !AppEnvironment.isProduction,
    );
    if (contentRef != null) {
      unawaited(_handleContentLink(contentRef));
      return;
    }

    WebSessionApprovalLink link;
    try {
      link = WebSessionApprovalLink.parse(
        uri,
        allowedRelayOrigins: const {AppEnvironment.defaultRelayBaseUrl},
        allowLocalHttp: !AppEnvironment.isProduction,
      );
    } catch (_) {
      _showWebSessionMessage('Invalid web session request.');
      return;
    }

    final did = _anchoredDid;
    if (did == null) {
      _showWebSessionMessage(
        'Create an app identity before approving web sessions.',
      );
      return;
    }

    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => WebSessionApprovalScreen(
          challengeId: link.challengeId,
          currentDid: did,
          client: WebSessionApprovalClient(baseUrl: link.relayOrigin),
        ),
      ),
    );
  }

  /// Resolves an inbound Elix content link against the local store and routes
  /// to the matching screen. Content that is not available locally surfaces a
  /// graceful message rather than a dead end.
  Future<void> _handleContentLink(ElixContentRef ref) async {
    final resolution = await ElixContentRouter(widget.db).resolve(ref);
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    switch (resolution) {
      case ResolvedThread(:final thread):
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PostsViewScreen(
              db: widget.db,
              thread: thread,
              authorDid: _anchoredDid,
            ),
          ),
        );
      case ResolvedBoard(:final board):
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadsListScreen(
              db: widget.db,
              board: board,
              localDid: _anchoredDid,
            ),
          ),
        );
      case ContentUnavailable():
        _showContentUnavailableMessage();
    }
  }

  void _showContentUnavailableMessage() {
    final context = _navigatorKey.currentContext;
    final message = context != null
        ? context.uiCopy(
            zh: '這個連結指向的內容尚未同步到這台裝置',
            en: 'That link points to content not yet on this device',
          )
        : 'That link points to content not yet on this device';
    _showWebSessionMessage(message);
  }

  bool _isMobileMoicaCallbackLink(Uri uri) {
    return uri.scheme == 'trisaura' &&
        uri.host == 'mobilemoica' &&
        (uri.path == '/callback' || uri.path.startsWith('/callback/'));
  }

  void _showWebSessionMessage(String message) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadPersistedIdentity() async {
    try {
      // Canonical did:elix is the source of truth. Guard its own load so a
      // missing/unavailable store falls through to the legacy DID managers
      // rather than aborting the whole identity load.
      CanonicalIdentity? canonical;
      try {
        canonical = await _canonicalIdentityStore.load();
      } catch (_) {
        canonical = null;
      }
      if (canonical != null) {
        final c = canonical;
        if (!mounted) return;
        setState(() {
          _anchoredDid = c.did;
          _anchoredPublicKeyHex = c.publicKeyHex;
          _loadingIdentity = false;
        });
        unawaited(_maybeNagForBackup());
        return;
      }

      // Legacy fallback: pre-did:elix accounts (did:plc stub / did:key).
      final plcDid = await _didPlcManager.loadDid();
      final ownedDid = plcDid == null ? await _didManager.load() : null;
      if (!mounted) return;
      setState(() {
        _anchoredDid = plcDid?.did ?? ownedDid?.did;
        _anchoredPublicKeyHex = plcDid?.publicKeyHex ?? ownedDid?.publicKeyHex;
        _loadingIdentity = false;
      });
      // recovery design Task 2 "nag-once": a user who skipped the at-creation
      // backup gets re-prompted on a later launch (exactly once). Never blocks
      // the app — it is a soft prompt opened over the home shell.
      unawaited(_maybeNagForBackup());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _anchoredDid = null;
        _anchoredPublicKeyHex = null;
        _loadingIdentity = false;
      });
    }
  }

  // After the v2 challenge-anchor succeeds (handle claimed), route through the
  // onboarding backup step rather than straight into the app. The backup step
  // (a) publishes the initial self-certifying anchor and (b) strongly offers a
  // skippable backup, then completes into the app via [_completeOnboarding].
  IdentityAnchorService _buildAnchorService() {
    return IdentityAnchorService(
      relayClient: RelayAnchorClient(),
      anchorRepository: DriftIdentityAnchorRepository(widget.db),
      deviceKeyStore: const SecureDeviceKeyStore(),
      readinessStore: const SharedPreferencesRecoveryReadinessStore(),
    );
  }

  void _handleRegistered(String did, String handle) {
    // recovery design Task 2 + 3: present the onboarding backup step (which
    // publishes the initial anchor + offers the backup) before entering the app.
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingBackupStepScreen(
          did: did,
          handle: handle,
          anchorService: _buildAnchorService(),
          onComplete: _completeOnboarding,
        ),
      ),
    );
  }

  void _completeOnboarding(String did) {
    // Pop the onboarding backup step (if still on the stack) and enter the app.
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _anchoredDid = did);
  }

  /// Nag-once: if the user skipped the at-creation backup, open the backup
  /// screen once over the home shell on this launch (then never again).
  Future<void> _maybeNagForBackup() async {
    final did = _anchoredDid;
    if (did == null) return;
    const store = SharedPreferencesRecoveryReadinessStore();
    if (!await store.shouldNagForBackup()) return;
    await store.markNagShown();
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => IdentityBackupScreen(
          did: did,
          identityPrivateKeyHex: () =>
              const FlutterSecureStorage().read(key: 'ansible_did_private_key'),
          readinessStore: store,
        ),
      ),
    );
  }

  Future<void> _installRecoveredKey(String privateKeyHex) {
    return const FlutterSecureStorage().write(
      key: 'ansible_did_private_key',
      value: privateKeyHex,
    );
  }

  void _openRecoveryWizard() {
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => RecoveryWizardScreen(
          service: _buildAnchorService(),
          installRecoveredKey: _installRecoveredKey,
          // Recover INTO the recovered account (same DID, same handle): enter
          // the app exactly as a fresh registration would, no new account.
          onRecovered: (did) {
            _navigatorKey.currentState?.popUntil((route) => route.isFirst);
            setState(() => _anchoredDid = did);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _localeController,
        themeController,
        _readingPreferencesController,
      ]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _scaffoldMessengerKey,
          title: AnsibleDesign.brandName,
          theme: AnsibleDesign.theme(),
          darkTheme: AnsibleDesign.darkTheme(),
          themeMode: themeController.mode,
          locale: _localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final effectiveScale = mediaQuery.textScaler.scale(
              _readingPreferencesController.textScaleFactor,
            );
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(effectiveScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _loadingIdentity
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : _anchoredDid != null
              ? HomeShell(
                  db: widget.db,
                  did: _anchoredDid!,
                  publicKeyHex: _anchoredPublicKeyHex,
                  localeController: _localeController,
                  readingPreferencesController: _readingPreferencesController,
                  onClearIdentity: () => setState(() => _anchoredDid = null),
                  initialBoard: widget.initialBoard,
                )
              : _introDone
              ? PasskeysRegistrationScreen(
                  onRegistered: _handleRegistered,
                  onRecoverExistingAccount: _openRecoveryWizard,
                )
              : OnboardingIntroScreen(
                  onContinue: () => setState(() => _introDone = true),
                ),
        );
      },
    );
  }
}
