import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class PublicProfileCredentialPreferenceStore {
  Future<Set<String>> selectedCredentialIds(String holderDid);

  Future<void> setSelected({
    required String holderDid,
    required String credentialId,
    required bool selected,
  });
}

class SecurePublicProfileCredentialPreferenceStore
    implements PublicProfileCredentialPreferenceStore {
  const SecurePublicProfileCredentialPreferenceStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static String _key(String holderDid) =>
      'elix.public-profile.credentials.${base64Url.encode(utf8.encode(holderDid))}';

  @override
  Future<Set<String>> selectedCredentialIds(String holderDid) async {
    final raw = await _storage.read(key: _key(holderDid));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }

  @override
  Future<void> setSelected({
    required String holderDid,
    required String credentialId,
    required bool selected,
  }) async {
    final ids = await selectedCredentialIds(holderDid);
    if (selected) {
      ids.add(credentialId);
    } else {
      ids.remove(credentialId);
    }
    if (ids.isEmpty) {
      await _storage.delete(key: _key(holderDid));
      return;
    }
    final ordered = ids.toList()..sort();
    await _storage.write(key: _key(holderDid), value: jsonEncode(ordered));
  }
}

class MemoryPublicProfileCredentialPreferenceStore
    implements PublicProfileCredentialPreferenceStore {
  final Map<String, Set<String>> _values = {};

  @override
  Future<Set<String>> selectedCredentialIds(String holderDid) async =>
      Set<String>.from(_values[holderDid] ?? const <String>{});

  @override
  Future<void> setSelected({
    required String holderDid,
    required String credentialId,
    required bool selected,
  }) async {
    final ids = _values.putIfAbsent(holderDid, () => <String>{});
    if (selected) {
      ids.add(credentialId);
    } else {
      ids.remove(credentialId);
    }
  }
}

bool isPublicProfileCredentialType(String credentialType) =>
    switch (credentialType) {
      'TrisAuraHumanityCredential' ||
      'AgeOver18Credential' ||
      'NationalityCredential' ||
      'TaiwanCitizenshipCredential' => true,
      _ => false,
    };

String publicProfileCredentialLabel(String credentialType) =>
    switch (credentialType) {
      'TrisAuraHumanityCredential' => '已驗證真人',
      'AgeOver18Credential' => '已滿 18 歲',
      'NationalityCredential' => '已驗證國籍',
      'TaiwanCitizenshipCredential' => '台灣公民',
      _ => credentialType,
    };
