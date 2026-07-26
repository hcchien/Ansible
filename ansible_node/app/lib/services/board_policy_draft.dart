import 'dart:convert';

enum BoardAudienceMode {
  public,
  verifiedHumanPost,
  taiwanCitizenPost,
  adultPost,
  memberPost,
  memberRead,
  customPost,
  customRead,
}

class BoardPolicyDraft {
  const BoardPolicyDraft({
    required this.mode,
    this.customRequirement,
    this.minPostTier,
  });

  final BoardAudienceMode mode;
  final Map<String, Object?>? customRequirement;
  final String? minPostTier;

  bool get requiresCredential => switch (mode) {
    BoardAudienceMode.taiwanCitizenPost ||
    BoardAudienceMode.adultPost ||
    BoardAudienceMode.memberPost ||
    BoardAudienceMode.memberRead ||
    BoardAudienceMode.customPost ||
    BoardAudienceMode.customRead => true,
    _ => false,
  };

  bool get restrictsReading => switch (mode) {
    BoardAudienceMode.memberRead || BoardAudienceMode.customRead => true,
    _ => false,
  };

  bool get isCustom => switch (mode) {
    BoardAudienceMode.customPost || BoardAudienceMode.customRead => true,
    _ => false,
  };

  String? get effectiveMinPostTier =>
      mode == BoardAudienceMode.verifiedHumanPost
      ? 'verified_human'
      : minPostTier;

  String get contentVisibility => restrictsReading ? 'host_visible' : 'public';
  String get federationMode => restrictsReading ? 'disabled' : 'enabled';

  Map<String, Object?> get postingPolicy => {
    if (effectiveMinPostTier != null) 'min_post_tier': effectiveMinPostTier,
  };

  Map<String, Object?> accessPolicy({required String systemIssuerDid}) {
    final requirement = _requirement(systemIssuerDid);
    return {
      'version': 1,
      'discovery': restrictsReading ? 'credential_required' : 'public',
      'read': {'requirement': restrictsReading ? 'member' : 'public'},
      'post': {'requirement': requiresCredential ? 'member' : 'posting_policy'},
      'moderate': {'requirement': 'board_moderator'},
      'requirements': requiresCredential ? {'member': requirement} : {},
      'capability_ttl_seconds': 300,
      'content_visibility': contentVisibility,
      'federation': federationMode,
    };
  }

  Map<String, Object?> _requirement(String systemIssuerDid) {
    if (customRequirement != null) return customRequirement!;
    return switch (mode) {
      BoardAudienceMode.taiwanCitizenPost => {
        'credential_type': 'NationalityCredential',
        'trusted_issuers': [systemIssuerDid],
        'claims': [
          {'path': 'nationalityVerified', 'op': 'equals', 'value': true},
          {'path': 'nationality', 'op': 'equals', 'value': 'TWN'},
        ],
        'holder_binding': 'required',
        'status': {'required': true, 'max_age_seconds': 300},
      },
      BoardAudienceMode.adultPost => _builtInRequirement(
        type: 'AgeOver18Credential',
        issuer: systemIssuerDid,
        path: 'ageOver18',
      ),
      BoardAudienceMode.memberPost ||
      BoardAudienceMode.memberRead => _builtInRequirement(
        type: 'PoliticalPartyMembershipCredential',
        issuer: systemIssuerDid,
        path: 'membership',
      ),
      _ => const {},
    };
  }

  String summary({required String systemIssuerDid}) {
    final audience = restrictsReading
        ? 'Only eligible members can discover and read this board.'
        : 'Everyone can discover and read this board.';
    final posting = switch (mode) {
      BoardAudienceMode.public => 'Anyone with posting permission can post.',
      BoardAudienceMode.verifiedHumanPost =>
        'Posting requires the verified-human tier.',
      BoardAudienceMode.taiwanCitizenPost =>
        'Posting requires a valid Taiwan citizenship credential.',
      BoardAudienceMode.adultPost =>
        'Posting requires a valid age-over-18 credential.',
      BoardAudienceMode.memberPost || BoardAudienceMode.memberRead =>
        'Posting requires a valid organization membership credential.',
      BoardAudienceMode.customPost || BoardAudienceMode.customRead =>
        'Posting requires the selected credential and minimum claim.',
    };
    final distribution = restrictsReading
        ? 'The Forum Host can read content; public search and federation are disabled.'
        : 'Content is public and federation is enabled.';
    return '$audience $posting $distribution';
  }

  static BoardPolicyDraft fromPolicies({
    Map<String, Object?> postingPolicy = const {},
    Map<String, Object?> accessPolicy = const {},
  }) {
    final tier = postingPolicy['min_post_tier'] as String?;
    final discovery = accessPolicy['discovery'];
    final read = accessPolicy['read'];
    final post = accessPolicy['post'];
    final requirements = accessPolicy['requirements'];
    final readRequirement = read is Map ? read['requirement'] : null;
    final postRequirement = post is Map ? post['requirement'] : null;
    final custom = requirements is Map && requirements['member'] is Map
        ? Map<String, Object?>.from(requirements['member'] as Map)
        : null;

    if (postRequirement == 'member' && custom != null) {
      final type = custom['credential_type'];
      final restricted =
          discovery == 'credential_required' || readRequirement == 'member';
      if (type == 'NationalityCredential' && !restricted) {
        return BoardPolicyDraft(
          mode: BoardAudienceMode.taiwanCitizenPost,
          customRequirement: custom,
        );
      }
      if (type == 'AgeOver18Credential' && !restricted) {
        return BoardPolicyDraft(
          mode: BoardAudienceMode.adultPost,
          customRequirement: custom,
        );
      }
      if (type == 'PoliticalPartyMembershipCredential') {
        return BoardPolicyDraft(
          mode: restricted
              ? BoardAudienceMode.memberRead
              : BoardAudienceMode.memberPost,
          customRequirement: custom,
        );
      }
      return BoardPolicyDraft(
        mode: restricted
            ? BoardAudienceMode.customRead
            : BoardAudienceMode.customPost,
        customRequirement: custom,
      );
    }
    if (tier == 'verified_human') {
      return const BoardPolicyDraft(mode: BoardAudienceMode.verifiedHumanPost);
    }
    return BoardPolicyDraft(mode: BoardAudienceMode.public, minPostTier: tier);
  }

  static Map<String, Object?> _builtInRequirement({
    required String type,
    required String issuer,
    required String path,
  }) => {
    'credential_type': type,
    'trusted_issuers': [issuer],
    'claims': [
      {'path': path, 'op': 'equals', 'value': true},
    ],
    'holder_binding': 'required',
    'status': {'required': true, 'max_age_seconds': 300},
  };
}

String canonicalPolicyJson(Map<String, Object?> policy) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList(growable: false);
    return value;
  }

  return const JsonEncoder.withIndent('  ').convert(canonical(policy));
}
