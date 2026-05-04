import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
// import 'screens/identity_anchor_screen.dart'; // V1: DID anchoring via NFC passport (replaced by PasskeysRegistrationScreen in V2.0)
import 'screens/passkeys_registration_screen.dart'; // V2.0: Passkeys registration
import 'services/relay_identity_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the Rust native library (Ed25519, did:key, signing).
  // Placeholder stub until ./setup_codegen.sh is run; after that it loads the
  // real .so / .dylib via flutter_rust_bridge.
  await RustLib.init();

  // Initialise local SQLite store (Drift schema v7).
  // No username/password — identity is DID-based.
  final db = AppDatabase();

  runApp(MyApp(db: db));
}

class MyApp extends StatefulWidget {
  final AppDatabase db;
  final DidManager? didManager;
  final DidPlcManager? didPlcManager;
  final DidSigner? didSigner;
  // ignore: unused_field — kept for V1 test-injection compatibility; V2.0 uses AtProtoClient
  final RelayIdentityClient? relayIdentityClient;

  const MyApp({
    super.key,
    required this.db,
    this.didManager,
    this.didPlcManager,
    this.didSigner,
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

  @override
  void initState() {
    super.initState();
    _didManager = widget.didManager ?? DidManagerImpl();
    _didPlcManager = widget.didPlcManager ?? DidPlcManagerImpl();
    _loadPersistedIdentity();
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
    const bgDeep = Color(0xFF050915);
    const bgLight = Color(0xFF0B1220);
    const accent = Color(0xFFFF9F43); // lively orange per latest UI
    const fontFamilyBase = 'PMingLiU'; // 新細明體
    const fontFallback = ['PMingLiU', 'MingLiU', 'PingFang TC'];
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: Colors.black,
      secondary: const Color(0xFFFFB76B),
      onSecondary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: const Color(0xFF0F182A),
      onSurface: Colors.white,
      surfaceContainerHighest: const Color(0xFF101728),
      onSurfaceVariant: const Color(0xFFA9B4C8),
      outline: const Color(0xFF1F2A3D),
      shadow: Colors.black,
      tertiary: accent.withOpacity(0.7),
      onTertiary: Colors.black,
    );

    return MaterialApp(
      title: 'Ansible Node',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: bgDeep,
        cardColor: colorScheme.surface,
        fontFamily: fontFamilyBase,
        fontFamilyFallback: fontFallback,
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
          fontFamilyFallback: fontFallback,
        ),
        primaryTextTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
          fontFamilyFallback: fontFallback,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bgLight,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFamily: fontFamilyBase,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF28334A)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: const TextStyle(fontFamily: fontFamilyBase),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
        useMaterial3: true,
      ),
      home: _loadingIdentity
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _anchoredDid != null
          ? HomeShell(
              db: widget.db,
              did: _anchoredDid!,
              onClearIdentity: () => setState(() => _anchoredDid = null),
            )
          : PasskeysRegistrationScreen(onRegistered: _handleRegistered),
    );
  }
}
