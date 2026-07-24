import 'package:ansible_node/services/board_policy_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const issuer = 'did:web:issuer.example';

  test('public intent generates an explicit public policy', () {
    const draft = BoardPolicyDraft(mode: BoardAudienceMode.public);
    final policy = draft.accessPolicy(systemIssuerDid: issuer);

    expect(draft.postingPolicy, isEmpty);
    expect(policy['discovery'], 'public');
    expect(policy['read'], {'requirement': 'public'});
    expect(policy['post'], {'requirement': 'posting_policy'});
    expect(policy['requirements'], isEmpty);
    expect(draft.contentVisibility, 'public');
    expect(draft.federationMode, 'enabled');
  });

  test('verified-human intent uses only the reputation gate', () {
    const draft = BoardPolicyDraft(
      mode: BoardAudienceMode.verifiedHumanPost,
    );
    final policy = draft.accessPolicy(systemIssuerDid: issuer);

    expect(draft.postingPolicy, {'min_post_tier': 'verified_human'});
    expect(policy['post'], {'requirement': 'posting_policy'});
    expect(policy['requirements'], isEmpty);
  });

  test('member-read intent disables public discovery and federation', () {
    const draft = BoardPolicyDraft(mode: BoardAudienceMode.memberRead);
    final policy = draft.accessPolicy(systemIssuerDid: issuer);
    final requirement =
        (policy['requirements'] as Map)['member'] as Map<String, Object?>;

    expect(policy['discovery'], 'credential_required');
    expect(policy['read'], {'requirement': 'member'});
    expect(policy['post'], {'requirement': 'member'});
    expect(draft.contentVisibility, 'host_visible');
    expect(draft.federationMode, 'disabled');
    expect(requirement['credential_type'], 'PoliticalPartyMembershipCredential');
    expect(requirement['trusted_issuers'], [issuer]);
  });

  test('existing custom policy round-trips without losing the requirement', () {
    final requirement = <String, Object?>{
      'credential_configuration_id': 'member-v2',
      'credential_type': 'OrganizationMembershipCredential',
      'trusted_issuers': ['did:web:party.example'],
      'claims': [
        {'path': 'membershipActive', 'op': 'equals', 'value': true},
      ],
      'holder_binding': 'required',
      'status': {'required': true, 'max_age_seconds': 300},
    };
    final draft = BoardPolicyDraft.fromPolicies(
      accessPolicy: {
        'version': 1,
        'discovery': 'credential_required',
        'read': {'requirement': 'member'},
        'post': {'requirement': 'member'},
        'requirements': {'member': requirement},
      },
    );

    expect(draft.mode, BoardAudienceMode.customRead);
    final regenerated = draft.accessPolicy(systemIssuerDid: issuer);
    expect((regenerated['requirements'] as Map)['member'], requirement);
  });
}
