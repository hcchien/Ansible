import 'dart:convert';
import 'dart:math';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import '../config/protocol.dart';
import 'canonical_identity_store.dart';
import 'identity_anchor_service.dart';
import 'relay_anchor_client.dart';

enum IdentityMigrationPhase { prepared, anchorPublished }

class IdentityMigrationCheckpoint {
  const IdentityMigrationCheckpoint({
    required this.legacyDid,
    required this.v1Did,
    required this.handle,
    required this.publicKeyHex,
    required this.signingAlgorithm,
    required this.custody,
    required this.genesisCommitment,
    required this.createdAt,
    required this.phase,
  });

  final String legacyDid;
  final String v1Did;
  final String handle;
  final String publicKeyHex;
  final String signingAlgorithm;
  final String custody;
  final Map<String, Object?> genesisCommitment;
  final DateTime createdAt;
  final IdentityMigrationPhase phase;

  IdentityMigrationCheckpoint copyWith({IdentityMigrationPhase? phase}) {
    return IdentityMigrationCheckpoint(
      legacyDid: legacyDid,
      v1Did: v1Did,
      handle: handle,
      publicKeyHex: publicKeyHex,
      signingAlgorithm: signingAlgorithm,
      custody: custody,
      genesisCommitment: genesisCommitment,
      createdAt: createdAt,
      phase: phase ?? this.phase,
    );
  }

  Map<String, Object?> toJson() => {
    'legacy_did': legacyDid,
    'v1_did': v1Did,
    'handle': handle,
    'public_key_hex': publicKeyHex,
    'signing_algorithm': signingAlgorithm,
    'custody': custody,
    'genesis_commitment': genesisCommitment,
    'created_at': _canonicalTimestamp(createdAt),
    'phase': phase.name,
  };

  factory IdentityMigrationCheckpoint.fromJson(Map<String, Object?> json) {
    return IdentityMigrationCheckpoint(
      legacyDid: json['legacy_did']! as String,
      v1Did: json['v1_did']! as String,
      handle: json['handle']! as String,
      publicKeyHex: json['public_key_hex']! as String,
      signingAlgorithm: json['signing_algorithm']! as String,
      custody: json['custody']! as String,
      genesisCommitment: (json['genesis_commitment']! as Map)
          .cast<String, Object?>(),
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
      phase: IdentityMigrationPhase.values.byName(json['phase']! as String),
    );
  }
}

abstract class IdentityMigrationCheckpointStore {
  Future<IdentityMigrationCheckpoint?> load();
  Future<void> save(IdentityMigrationCheckpoint checkpoint);
  Future<void> delete();
}

class SecureIdentityMigrationCheckpointStore
    implements IdentityMigrationCheckpointStore {
  const SecureIdentityMigrationCheckpointStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ansible_identity_migration_checkpoint_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<IdentityMigrationCheckpoint?> load() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid identity migration checkpoint.');
    }
    return IdentityMigrationCheckpoint.fromJson(decoded);
  }

  @override
  Future<void> save(IdentityMigrationCheckpoint checkpoint) {
    return _storage.write(key: _key, value: jsonEncode(checkpoint.toJson()));
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class InMemoryIdentityMigrationCheckpointStore
    implements IdentityMigrationCheckpointStore {
  IdentityMigrationCheckpoint? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<IdentityMigrationCheckpoint?> load() async => value;

  @override
  Future<void> save(IdentityMigrationCheckpoint checkpoint) async {
    value = checkpoint;
  }
}

class IdentityMigrationRecord {
  const IdentityMigrationRecord({
    required this.legacyDid,
    required this.v1Did,
    required this.handle,
    required this.state,
    required this.canonicalBody,
  });

  final String legacyDid;
  final String v1Did;
  final String handle;
  final String state;
  final String canonicalBody;

  factory IdentityMigrationRecord.fromJson(Map<String, dynamic> json) {
    return IdentityMigrationRecord(
      legacyDid: json['legacy_did']! as String,
      v1Did: json['v1_did']! as String,
      handle: json['handle']! as String,
      state: json['state'] as String? ?? 'completed',
      canonicalBody: json['canonical_body']! as String,
    );
  }
}

class IdentityMigrationException implements Exception {
  const IdentityMigrationException({
    required this.code,
    this.statusCode = 0,
    this.retryable = false,
  });

  final String code;
  final int statusCode;
  final bool retryable;

  @override
  String toString() => 'IdentityMigrationException($statusCode $code)';
}

class RelayIdentityMigrationClient {
  RelayIdentityMigrationClient({
    String baseUrl = AppEnvironment.defaultRelayBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUri = Uri.parse(baseUrl),
       _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;
  final Duration timeout;

  Future<IdentityMigrationRecord?> fetch(String legacyDid) async {
    final response = await _client
        .get(
          _endpoint(
            '/api/v1/identity/migration/${Uri.encodeComponent(legacyDid)}',
          ),
          headers: AnsibleProtocol.headers,
        )
        .timeout(timeout);
    if (response.statusCode == 404) return null;
    return _decodeSuccess(response);
  }

  Future<IdentityMigrationRecord> submit(Map<String, Object?> payload) async {
    final response = await _client
        .post(
          _endpoint('/api/v1/identity/migration'),
          headers: const {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    return _decodeSuccess(response);
  }

  IdentityMigrationRecord _decodeSuccess(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } catch (_) {
      throw IdentityMigrationException(
        code: 'invalid_relay_response',
        statusCode: response.statusCode,
        retryable: response.statusCode >= 500,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw IdentityMigrationException(
        code: decoded['error'] as String? ?? 'migration_failed',
        statusCode: response.statusCode,
        retryable: decoded['retryable'] == true || response.statusCode >= 500,
      );
    }
    return IdentityMigrationRecord.fromJson(decoded);
  }

  Uri _endpoint(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path');
  }

  void close() => _client.close();
}

class IdentityMigrationService {
  IdentityMigrationService({
    required this.anchorService,
    required this.anchorRepository,
    RelayAnchorClient? anchorClient,
    RelayIdentityMigrationClient? migrationClient,
    CanonicalIdentityStore? identityStore,
    IdentityMigrationCheckpointStore? checkpointStore,
    this.identityKey,
    FlutterSecureStorage? metadataStorage,
    DateTime Function()? now,
    String Function()? nonceHex,
  }) : anchorClient = anchorClient ?? anchorService.relayClient,
       migrationClient = migrationClient ?? RelayIdentityMigrationClient(),
       identityStore = identityStore ?? const SecureCanonicalIdentityStore(),
       checkpointStore =
           checkpointStore ?? const SecureIdentityMigrationCheckpointStore(),
       _metadataStorage = metadataStorage ?? const FlutterSecureStorage(),
       now = now ?? (() => DateTime.now().toUtc()),
       nonceHex = nonceHex ?? _secureNonceHex;

  final IdentityAnchorService anchorService;
  final IdentityAnchorRepository anchorRepository;
  final RelayAnchorClient anchorClient;
  final RelayIdentityMigrationClient migrationClient;
  final CanonicalIdentityStore identityStore;
  final IdentityMigrationCheckpointStore checkpointStore;
  final IdentityKey? identityKey;
  final FlutterSecureStorage _metadataStorage;
  final DateTime Function() now;
  final String Function() nonceHex;

  static final RegExp _v1Did = RegExp(r'^did:elix:z[a-z2-7]{52}$');
  static final RegExp _legacyDid = RegExp(r'^did:elix:[a-z2-7]{10,}$');

  Future<bool> isEligible() async {
    final identity = await identityStore.load();
    return identity != null &&
        _legacyDid.hasMatch(identity.did) &&
        !_v1Did.hasMatch(identity.did);
  }

  /// Whether resuming this checkpoint still needs private-key operations.
  /// A Relay-completed migration is confirmed and finalized without opening a
  /// biometric session, avoiding an authentication prompt for a read-only
  /// recovery path after a timeout or process restart.
  Future<bool> requiresSigning() async {
    final current = await identityStore.load();
    if (current == null || _v1Did.hasMatch(current.did)) return false;
    final checkpoint = await checkpointStore.load();
    if (checkpoint == null) return true;
    final completed = await migrationClient.fetch(checkpoint.legacyDid);
    if (completed == null) return true;
    _validateCheckpoint(checkpoint, current);
    _validateCompletion(completed, checkpoint);
    return false;
  }

  Future<CanonicalIdentity> migrate({
    bool reuseAuthenticationContext = false,
  }) async {
    final current = await identityStore.load();
    if (current == null) {
      throw const IdentityMigrationException(
        code: 'canonical_identity_missing',
      );
    }

    var checkpoint = await checkpointStore.load();
    if (_v1Did.hasMatch(current.did)) {
      if (checkpoint != null && checkpoint.v1Did == current.did) {
        final existing = await migrationClient.fetch(checkpoint.legacyDid);
        _validateCompletion(existing, checkpoint);
        await _syncIdentityMetadata(current);
        await checkpointStore.delete();
      }
      return current;
    }
    if (!_legacyDid.hasMatch(current.did)) {
      throw const IdentityMigrationException(code: 'unsupported_legacy_did');
    }

    checkpoint ??= await _prepare(current);
    _validateCheckpoint(checkpoint, current);

    final alreadyCompleted = await migrationClient.fetch(checkpoint.legacyDid);
    if (alreadyCompleted != null) {
      _validateCompletion(alreadyCompleted, checkpoint);
      return _finalize(current, checkpoint);
    }

    final signer =
        identityKey ??
        ActiveIdentityKey(
          identityStore: identityStore,
          reuseAuthenticationContext: reuseAuthenticationContext,
        );
    await _validateLegacyAnchor(current, signer);
    await _ensureV1Anchor(checkpoint, signer);

    if (checkpoint.phase != IdentityMigrationPhase.anchorPublished) {
      checkpoint = checkpoint.copyWith(
        phase: IdentityMigrationPhase.anchorPublished,
      );
      await checkpointStore.save(checkpoint);
    }

    final unsigned = <String, Object?>{
      'type': 'io.trisaura.identity.migration',
      'version': 1,
      'legacy_did': checkpoint.legacyDid,
      'v1_did': checkpoint.v1Did,
      'created_at': _canonicalTimestamp(checkpoint.createdAt),
    };
    final body = jsonEncode(unsigned);
    final bytes = utf8.encode(body);
    // This product migration deliberately keeps the currently active account
    // key. Both proof fields therefore validate the same detached signature;
    // signing once avoids a redundant biometric prompt.
    final migrationSig = await signer.sign(bytes);

    await migrationClient.submit({
      ...unsigned,
      'legacy_sig': migrationSig,
      'v1_sig': migrationSig,
    });
    final confirmed = await migrationClient.fetch(checkpoint.legacyDid);
    _validateCompletion(confirmed, checkpoint);
    return _finalize(current, checkpoint);
  }

  Future<IdentityMigrationCheckpoint> _prepare(
    CanonicalIdentity current,
  ) async {
    final nonce = nonceHex();
    final commitment = buildDidElixV1GenesisCommitment(
      genesisKey: current.publicKeyHex,
      genesisNonceHex: nonce,
    );
    final checkpoint = IdentityMigrationCheckpoint(
      legacyDid: current.did,
      v1Did: deriveDidElixV1(
        genesisKey: current.publicKeyHex,
        genesisNonceHex: nonce,
      ),
      handle: current.handle,
      publicKeyHex: current.publicKeyHex,
      signingAlgorithm: current.signingAlgorithm,
      custody: current.custody,
      genesisCommitment: commitment,
      createdAt: _millisecondPrecision(now()),
      phase: IdentityMigrationPhase.prepared,
    );
    await checkpointStore.save(checkpoint);
    return checkpoint;
  }

  void _validateCheckpoint(
    IdentityMigrationCheckpoint checkpoint,
    CanonicalIdentity current,
  ) {
    final derived = deriveDidElixV1(
      genesisKey: checkpoint.publicKeyHex,
      genesisNonceHex: checkpoint.genesisCommitment['genesis_nonce']! as String,
    );
    if (checkpoint.legacyDid != current.did ||
        checkpoint.handle != current.handle ||
        checkpoint.publicKeyHex != current.publicKeyHex ||
        checkpoint.signingAlgorithm != current.signingAlgorithm ||
        checkpoint.v1Did != derived) {
      throw const IdentityMigrationException(
        code: 'migration_checkpoint_mismatch',
      );
    }
  }

  Future<void> _validateLegacyAnchor(
    CanonicalIdentity current,
    IdentityKey signer,
  ) async {
    final anchor = await anchorClient.fetchActiveAnchor(current.did);
    if (anchor == null) {
      throw const IdentityMigrationException(code: 'legacy_anchor_missing');
    }
    if (anchor.handle != current.handle ||
        anchor.identityKey.toLowerCase() !=
            current.publicKeyHex.toLowerCase() ||
        anchor.identityKeyAlgorithm != current.signingAlgorithm ||
        (await signer.publicKeyHex()).toLowerCase() !=
            current.publicKeyHex.toLowerCase()) {
      throw const IdentityMigrationException(
        code: 'legacy_identity_key_mismatch',
      );
    }
  }

  Future<void> _ensureV1Anchor(
    IdentityMigrationCheckpoint checkpoint,
    IdentityKey signer,
  ) async {
    final remote = await anchorClient.fetchActiveAnchor(checkpoint.v1Did);
    if (remote != null) {
      _validateV1Anchor(remote, checkpoint);
      return;
    }

    final local = await anchorRepository.latest(checkpoint.v1Did);
    if (local != null) {
      _validateV1Anchor(local, checkpoint);
      await anchorClient.submitAnchor(local);
      return;
    }

    await anchorService.publishInitialAnchor(
      did: checkpoint.v1Did,
      handle: checkpoint.handle,
      identityKey: signer,
      genesisCommitment: checkpoint.genesisCommitment,
    );
  }

  void _validateV1Anchor(
    IdentityAnchor anchor,
    IdentityMigrationCheckpoint checkpoint,
  ) {
    if (anchor.schemaVersion != IdentityAnchor.currentSchemaVersion ||
        anchor.did != checkpoint.v1Did ||
        anchor.handle != checkpoint.handle ||
        anchor.identityKey.toLowerCase() !=
            checkpoint.publicKeyHex.toLowerCase() ||
        anchor.identityKeyAlgorithm != checkpoint.signingAlgorithm ||
        jsonEncode(anchor.genesisCommitment) !=
            jsonEncode(checkpoint.genesisCommitment)) {
      throw const IdentityMigrationException(code: 'v1_anchor_mismatch');
    }
  }

  void _validateCompletion(
    IdentityMigrationRecord? record,
    IdentityMigrationCheckpoint checkpoint,
  ) {
    final expectedBody = jsonEncode(<String, Object?>{
      'type': 'io.trisaura.identity.migration',
      'version': 1,
      'legacy_did': checkpoint.legacyDid,
      'v1_did': checkpoint.v1Did,
      'created_at': _canonicalTimestamp(checkpoint.createdAt),
    });
    if (record == null ||
        record.state != 'completed' ||
        record.legacyDid != checkpoint.legacyDid ||
        record.v1Did != checkpoint.v1Did ||
        record.handle != checkpoint.handle ||
        record.canonicalBody != expectedBody) {
      throw const IdentityMigrationException(
        code: 'migration_confirmation_mismatch',
      );
    }
  }

  Future<CanonicalIdentity> _finalize(
    CanonicalIdentity current,
    IdentityMigrationCheckpoint checkpoint,
  ) async {
    final migrated = CanonicalIdentity(
      did: checkpoint.v1Did,
      handle: current.handle,
      publicKeyHex: current.publicKeyHex,
      signingAlgorithm: current.signingAlgorithm,
      custody: current.custody,
      genesisCommitment: checkpoint.genesisCommitment,
      legacyDids: {
        ...current.legacyDids,
        checkpoint.legacyDid,
      }.toList(growable: false),
    );
    await identityStore.save(migrated);
    await _syncIdentityMetadata(migrated);
    await checkpointStore.delete();
    return migrated;
  }

  Future<void> _syncIdentityMetadata(CanonicalIdentity identity) async {
    await _metadataStorage.write(
      key: 'ansible_passkeys_did',
      value: identity.did,
    );
    await _metadataStorage.write(
      key: 'ansible_passkeys_handle',
      value: identity.handle.split('.').first,
    );
  }
}

String _secureNonceHex() {
  final random = Random.secure();
  return List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

DateTime _millisecondPrecision(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  );
}

String _canonicalTimestamp(DateTime value) {
  return _millisecondPrecision(value).toIso8601String();
}
