import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/protocol.dart';
import 'sync_capability_service.dart';

enum FediverseDomainPolicy { open, allowlist }

typedef FediverseSyncCapabilityProvider =
    Future<String> Function(RemoteNode node);

@immutable
class FediversePreferences {
  const FediversePreferences({
    this.enabled = false,
    this.defaultNoteVisibility = 'public',
    this.allowRemoteFollowers = true,
    this.domainPolicy = FediverseDomainPolicy.open,
    this.allowedDomains = const [],
    this.blockedDomains = const [],
    this.blockedActors = const [],
    this.revision = 0,
  });

  final bool enabled;
  final String defaultNoteVisibility;
  final bool allowRemoteFollowers;
  final FediverseDomainPolicy domainPolicy;
  final List<String> allowedDomains;
  final List<String> blockedDomains;
  final List<String> blockedActors;
  final int revision;

  FediversePreferences copyWith({
    bool? enabled,
    String? defaultNoteVisibility,
    bool? allowRemoteFollowers,
    FediverseDomainPolicy? domainPolicy,
    List<String>? allowedDomains,
    List<String>? blockedDomains,
    List<String>? blockedActors,
    int? revision,
  }) => FediversePreferences(
    enabled: enabled ?? this.enabled,
    defaultNoteVisibility: defaultNoteVisibility ?? this.defaultNoteVisibility,
    allowRemoteFollowers: allowRemoteFollowers ?? this.allowRemoteFollowers,
    domainPolicy: domainPolicy ?? this.domainPolicy,
    allowedDomains: allowedDomains ?? this.allowedDomains,
    blockedDomains: blockedDomains ?? this.blockedDomains,
    blockedActors: blockedActors ?? this.blockedActors,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'default_note_visibility': defaultNoteVisibility,
    'allow_remote_followers': allowRemoteFollowers,
    'domain_policy': domainPolicy.name,
    'allowed_domains': allowedDomains,
    'blocked_domains': blockedDomains,
    'blocked_actors': blockedActors,
    'revision': revision,
  };

  factory FediversePreferences.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List? ?? const []).whereType<String>().toList()..sort();

    return FediversePreferences(
      enabled: json['enabled'] as bool? ?? false,
      defaultNoteVisibility:
          json['default_note_visibility'] as String? ?? 'public',
      allowRemoteFollowers: json['allow_remote_followers'] as bool? ?? true,
      domainPolicy: json['domain_policy'] == 'allowlist'
          ? FediverseDomainPolicy.allowlist
          : FediverseDomainPolicy.open,
      allowedDomains: strings('allowed_domains'),
      blockedDomains: strings('blocked_domains'),
      blockedActors: strings('blocked_actors'),
      revision: json['revision'] as int? ?? 0,
    );
  }
}

abstract class FediversePreferencesStore {
  Future<FediversePreferences> load(String did);
  Future<void> save(String did, FediversePreferences preferences);
}

class SharedPreferencesFediversePreferencesStore
    implements FediversePreferencesStore {
  const SharedPreferencesFediversePreferencesStore();

  String _key(String did) => 'fediverse_preferences.$did';

  @override
  Future<FediversePreferences> load(String did) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(did));
    if (raw == null) return const FediversePreferences();
    return FediversePreferences.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(String did, FediversePreferences preferences) async {
    await (await SharedPreferences.getInstance()).setString(
      _key(did),
      jsonEncode(preferences.toJson()),
    );
  }
}

class FediversePreferencesController extends ChangeNotifier {
  FediversePreferencesController({
    required this.did,
    required this.remoteNodes,
    FediversePreferencesStore store =
        const SharedPreferencesFediversePreferencesStore(),
    DidSigner? signer,
    http.Client? client,
    FediverseSyncCapabilityProvider? syncCapabilityProvider,
  }) : _store = store,
       _signer = signer ?? DidSignerImpl(),
       _client = client ?? http.Client(),
       _syncCapabilityProvider =
           syncCapabilityProvider ??
           ((node) async {
             final capability = await SyncCapabilityService(
               baseUrl: node.url,
               holderDid: did,
             ).authorize();
             return capability.token;
           });

  final String did;
  final RemoteNodeRepository remoteNodes;
  final FediversePreferencesStore _store;
  final DidSigner _signer;
  final http.Client _client;
  final FediverseSyncCapabilityProvider _syncCapabilityProvider;

  FediversePreferences preferences = const FediversePreferences();
  bool loaded = false;
  bool saving = false;

  Future<void> load() async {
    preferences = await _store.load(did);
    loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) =>
      update(preferences.copyWith(enabled: enabled));

  Future<int> deleteFederatedAccount() async {
    if (saving) return 0;
    saving = true;
    notifyListeners();
    try {
      final node = await remoteNodes.getActive();
      if (node == null) {
        throw StateError('No active Relay is configured.');
      }
      final requestedAt = DateTime.now().toUtc().toIso8601String();
      const reason = 'user_requested';
      final capability = await _syncCapabilityProvider(node);
      final payload = jsonEncode([
        did,
        'delete_fediverse_account',
        reason,
        requestedAt,
      ]);
      final signature = await _signer.sign(utf8.encode(payload));
      final response = await _client.post(
        Uri.parse(
          '${node.url.replaceFirst(RegExp(r'/$'), '')}'
          '/api/v1/fediverse/account/delete',
        ),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $capability',
          ...AnsibleProtocol.headers,
        },
        body: jsonEncode({
          'did': did,
          'reason_code': reason,
          'requested_at': requestedAt,
          'signature': signature.hex.toLowerCase(),
          'signature_scheme': signature.hex.length == 128
              ? 'ed25519'
              : 'p256-sha256',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(_error(response.body));
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      preferences = preferences.copyWith(
        enabled: false,
        allowRemoteFollowers: false,
      );
      await _store.save(did, preferences);
      return body['queued_delete_deliveries'] as int? ?? 0;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> update(FediversePreferences next) async {
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      final revision = DateTime.now().toUtc().microsecondsSinceEpoch;
      final normalized = next.copyWith(
        allowedDomains: _domains(next.allowedDomains),
        blockedDomains: _domains(next.blockedDomains),
        blockedActors: _actors(next.blockedActors),
        revision: revision > preferences.revision
            ? revision
            : preferences.revision + 1,
      );
      final node = await remoteNodes.getActive();
      if (node == null) {
        throw StateError('No active Relay is configured.');
      }
      final signature = await _signer.sign(
        utf8.encode(_signingPayload(normalized)),
      );
      final capability = await _syncCapabilityProvider(node);
      final body = {
        'did': did,
        ...normalized.toJson(),
        'signature': signature.hex.toLowerCase(),
        'signature_scheme': signature.hex.length == 128
            ? 'ed25519'
            : 'p256-sha256',
      };
      final response = await _client.put(
        Uri.parse(
          '${node.url.replaceFirst(RegExp(r'/$'), '')}'
          '/api/v1/fediverse/preferences',
        ),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $capability',
          ...AnsibleProtocol.headers,
        },
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _error(response.body);
        throw StateError(error);
      }
      final saved = FediversePreferences.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      preferences = saved;
      await _store.save(did, saved);
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  String _signingPayload(FediversePreferences value) => jsonEncode([
    did,
    value.enabled,
    value.defaultNoteVisibility,
    value.allowRemoteFollowers,
    value.domainPolicy.name,
    value.allowedDomains,
    value.blockedDomains,
    value.blockedActors,
    value.revision,
  ]);

  static List<String> _domains(List<String> values) =>
      values
          .map(
            (value) =>
                value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), ''),
          )
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  static List<String> _actors(List<String> values) =>
      values
          .map((value) => value.trim())
          .where((value) {
            final uri = Uri.tryParse(value);
            return uri?.scheme == 'https' && uri?.host.isNotEmpty == true;
          })
          .toSet()
          .toList()
        ..sort();

  static String _error(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['error'] as String? ??
          'Relay rejected the Fediverse preference.';
    } catch (_) {
      return 'Relay rejected the Fediverse preference.';
    }
  }
}
