import 'dart:io';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'screens/home_shell.dart';
// import 'screens/identity_anchor_screen.dart'; // V1: DID anchoring via NFC passport (replaced by PasskeysRegistrationScreen in V2.0)
import 'screens/passkeys_registration_screen.dart'; // V2.0: Passkeys registration
import 'services/relay_identity_client.dart';
import 'theme/ansible_design.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the Rust native library (Ed25519, did:key, signing).
  // Placeholder stub until ./setup_codegen.sh is run; after that it loads the
  // real .so / .dylib via flutter_rust_bridge.
  await RustLib.init();
  await _resetLocalIdentityIfRequested();

  // Initialise local SQLite store (Drift schema v7).
  // No username/password — identity is DID-based.
  final db = await _openAppDatabase();

  runApp(MyApp(db: db));
}

Future<AppDatabase> _openAppDatabase() async {
  final dbFolder = await getApplicationSupportDirectory();
  await dbFolder.create(recursive: true);
  final file = File(p.join(dbFolder.path, 'ansible.db'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}

Future<void> _resetLocalIdentityIfRequested() async {
  const reset = bool.fromEnvironment(
    'ANSIBLE_RESET_LOCAL_IDENTITY_ON_START',
    defaultValue: false,
  );
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
    return MaterialApp(
      title: 'Ansible Node',
      theme: AnsibleDesign.theme(),
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
