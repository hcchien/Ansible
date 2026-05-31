import 'dart:async';
import 'dart:io';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:app_links/app_links.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'config/app_environment.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_shell.dart';
// import 'screens/identity_anchor_screen.dart'; // V1: DID anchoring via NFC passport (replaced by PasskeysRegistrationScreen in V2.0)
import 'screens/passkeys_registration_screen.dart'; // V2.0: Passkeys registration
import 'screens/web_session_approval_screen.dart';
import 'services/app_locale_controller.dart';
import 'services/backup_policy_service.dart';
import 'services/reading_preferences_controller.dart';
import 'services/relay_identity_client.dart';
import 'services/web_session_approval_client.dart';
import 'services/web_session_grant_service.dart';
import 'theme/ansible_design.dart';

final ElixThemeController themeController = ElixThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.validateRuntimeReadiness(
    isReleaseBuild: kReleaseMode,
    usesDevelopmentRustBridge: !AppEnvironment.hasRealRustBridge,
  );

  // Initialise the Rust native library (Ed25519, did:key, signing).
  // Placeholder stub until ./setup_codegen.sh is run; after that it loads the
  // real .so / .dylib via flutter_rust_bridge.
  await RustLib.init();
  await _resetLocalIdentityIfRequested();

  // Load persisted theme before the first frame.
  await themeController.load();

  // Initialise local SQLite store (Drift schema v7).
  // No username/password — identity is DID-based.
  final storagePaths = await BackupPolicyService().prepareStorage();
  final db = await _openAppDatabase(storagePaths: storagePaths);

  runApp(MyApp(db: db, webSessionLinks: AppLinks().uriLinkStream));
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

  await DidPlcManagerImpl().deleteDid();
  await PasskeysManagerImpl().delete();
  await DidManagerImpl().delete();
}

class MyApp extends StatefulWidget {
  final AppDatabase db;
  final DidManager? didManager;
  final DidPlcManager? didPlcManager;
  final DidSigner? didSigner;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final Stream<Uri>? webSessionLinks;
  // ignore: unused_field — kept for V1 test-injection compatibility; V2.0 uses AtProtoClient
  final RelayIdentityClient? relayIdentityClient;

  const MyApp({
    super.key,
    required this.db,
    this.didManager,
    this.didPlcManager,
    this.didSigner,
    this.localeController,
    this.readingPreferencesController,
    this.webSessionLinks,
    this.relayIdentityClient,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Identity state: null = not anchored, non-null = DID string
  String? _anchoredDid;
  bool _loadingIdentity = true;
  late final DidManager _didManager;
  late final DidPlcManager _didPlcManager;
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
      final plcDid = await _didPlcManager.loadDid();
      final ownedDid = plcDid == null ? await _didManager.load() : null;
      if (!mounted) return;
      setState(() {
        _anchoredDid = plcDid?.did ?? ownedDid?.did;
        _loadingIdentity = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _anchoredDid = null;
        _loadingIdentity = false;
      });
    }
  }

  void _handleRegistered(String did) {
    setState(() => _anchoredDid = did);
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
                  localeController: _localeController,
                  readingPreferencesController: _readingPreferencesController,
                  onClearIdentity: () => setState(() => _anchoredDid = null),
                )
              : PasskeysRegistrationScreen(onRegistered: _handleRegistered),
        );
      },
    );
  }
}
