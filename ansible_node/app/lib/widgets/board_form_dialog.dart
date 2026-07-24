import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/hosted_issuer_manifest.dart';
import '../services/posting_gate.dart';

class BoardFormDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialDescription;
  final List<RemoteNode> forumHosts;
  final String? initialForumHostId;
  final bool requireForumHost;

  /// Shows the posting-policy (who can post) selector without requiring a
  /// forum-host picker — used when editing an existing hosted board.
  final bool showPostingPolicy;

  /// Current `posting_policy.min_post_tier` when editing; null ⇒ ungated.
  final String? initialMinPostTier;
  final HostedIssuerManifestLoader? manifestLoader;

  const BoardFormDialog({
    super.key,
    this.initialTitle,
    this.initialDescription,
    this.forumHosts = const [],
    this.initialForumHostId,
    this.requireForumHost = false,
    this.showPostingPolicy = false,
    this.initialMinPostTier,
    this.manifestLoader,
  });

  @override
  State<BoardFormDialog> createState() => _BoardFormDialogState();
}

class _BoardFormDialogState extends State<BoardFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _trustedIssuerController;
  late final TextEditingController _manifestUrlController;
  late final TextEditingController _claimValueController;
  final _formKey = GlobalKey<FormState>();
  String? _selectedForumHostId;

  /// `posting_policy.min_post_tier` for the new board; null ⇒ no gate.
  String? _minPostTier;
  String _accessMode = 'public';
  String _memberCredentialPreset = 'taiwan_citizenship';
  HostedIssuerManifest? _issuerManifest;
  HostedIssuerCredentialConfiguration? _credentialConfiguration;
  HostedIssuerClaimConfiguration? _claimConfiguration;
  String? _manifestError;
  var _loadingManifest = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _trustedIssuerController = TextEditingController();
    _manifestUrlController = TextEditingController();
    _claimValueController = TextEditingController(text: 'true');
    _selectedForumHostId =
        widget.initialForumHostId ??
        (widget.forumHosts.isNotEmpty ? widget.forumHosts.first.id : null);
    _minPostTier = widget.initialMinPostTier;
  }

  bool get _showsPostingPolicy =>
      widget.requireForumHost || widget.showPostingPolicy;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _trustedIssuerController.dispose();
    _manifestUrlController.dispose();
    _claimValueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialTitle == null
            ? context.uiCopy(zh: '建立託管看板', en: 'Create hosted board')
            : context.uiCopy(zh: '編輯託管看板', en: 'Edit hosted board'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.requireForumHost) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedForumHostId,
                  items: widget.forumHosts
                      .map(
                        (host) => DropdownMenuItem(
                          value: host.id,
                          child: Text(host.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedForumHostId = value);
                  },
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: 'Elix Relay',
                      en: 'Elix Relay',
                    ),
                  ),
                  validator: (_) {
                    if (!widget.requireForumHost) return null;
                    if (_selectedForumHostId == null ||
                        _selectedForumHostId!.isEmpty) {
                      return context.uiCopy(
                        zh: '請選擇 Elix Relay',
                        en: 'Select an Elix Relay',
                      );
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '標題', en: 'Title'),
                  hintText: context.uiCopy(
                    zh: '輸入託管看板標題',
                    en: 'Enter hosted board title',
                  ),
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return context.uiCopy(zh: '請輸入標題', en: 'Title is required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: context.uiCopy(
                    zh: '描述（選填）',
                    en: 'Description (optional)',
                  ),
                  hintText: context.uiCopy(
                    zh: '輸入看板描述',
                    en: 'Enter board description',
                  ),
                ),
                maxLines: 3,
              ),
              if (_showsPostingPolicy) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _minPostTier,
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.uiCopy(zh: '不限', en: 'Anyone')),
                    ),
                    DropdownMenuItem<String?>(
                      value: PostingGate.verifiedHumanTier,
                      child: Text(
                        context.uiCopy(zh: '需真人驗證', en: 'Verified humans only'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _minPostTier = value);
                  },
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '額外真人門檻',
                      en: 'Additional personhood gate',
                    ),
                    helperText: context.uiCopy(
                      zh: '通常選「不限」；需要特定 VC 時請使用下方的看板存取設定。',
                      en: 'Usually leave this as Anyone; use board access below for a specific VC.',
                    ),
                  ),
                ),
              ],
              if (widget.requireForumHost) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _accessMode,
                  items: [
                    DropdownMenuItem(
                      value: 'public',
                      child: Text(
                        context.uiCopy(zh: '公開看板', en: 'Public board'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'member_post',
                      child: Text(
                        context.uiCopy(zh: '會員才能發文', en: 'Members can post'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'member_read',
                      child: Text(
                        context.uiCopy(
                          zh: '會員才能發現與閱讀',
                          en: 'Members can discover and read',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _accessMode = value ?? 'public'),
                  decoration: InputDecoration(
                    labelText: context.uiCopy(zh: '看板存取', en: 'Board access'),
                    helperText: context.uiCopy(
                      zh: '會員資格只適用於這個看板，不會提高全域信任等級。',
                      en: 'Membership applies only to this board and never changes global reputation.',
                    ),
                  ),
                ),
                if (_accessMode != 'public') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('member_credential_preset'),
                    initialValue: _memberCredentialPreset,
                    items: [
                      DropdownMenuItem(
                        value: 'taiwan_citizenship',
                        child: Text(
                          context.uiCopy(zh: '台灣公民', en: 'Taiwan citizenship'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'age_over_18',
                        child: Text(
                          context.uiCopy(zh: '年滿 18 歲', en: 'Age 18 or older'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text(
                          context.uiCopy(
                            zh: '自訂憑證（進階）',
                            en: 'Custom credential (advanced)',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _memberCredentialPreset =
                          value ?? 'taiwan_citizenship',
                    ),
                    decoration: InputDecoration(
                      labelText: context.uiCopy(
                        zh: '所需資格',
                        en: 'Required credential',
                      ),
                      helperText: context.uiCopy(
                        zh: 'App 會自動選擇可信簽發者與最少揭露條件。',
                        en: 'The app selects the trusted issuer and minimum-disclosure claim.',
                      ),
                    ),
                  ),
                  if (_memberCredentialPreset == 'custom') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('hosted_issuer_manifest_url'),
                      controller: _manifestUrlController,
                      decoration: InputDecoration(
                        labelText: context.uiCopy(
                          zh: 'Hosted Issuer Manifest URL',
                          en: 'Hosted Issuer manifest URL',
                        ),
                        hintText:
                            'https://issuer.example/api/v1/hosted-issuers/org/manifest',
                        suffixIcon: _loadingManifest
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                key: const Key('load_issuer_manifest'),
                                onPressed: _loadManifest,
                                icon: const Icon(Icons.download_outlined),
                                tooltip: context.uiCopy(
                                  zh: '載入憑證設定',
                                  en: 'Load credential configurations',
                                ),
                              ),
                        errorText: _manifestError,
                      ),
                    ),
                    if (_issuerManifest != null &&
                        _issuerManifest!.configurations.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<
                        HostedIssuerCredentialConfiguration
                      >(
                        key: const Key('credential_configuration'),
                        isExpanded: true,
                        initialValue: _credentialConfiguration,
                        items: _issuerManifest!.configurations
                            .map(
                              (configuration) => DropdownMenuItem(
                                value: configuration,
                                child: Text(
                                  '${configuration.id} · ${configuration.credentialType}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (configuration) {
                          setState(() {
                            _credentialConfiguration = configuration;
                            _claimConfiguration =
                                configuration?.claims.firstOrNull;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: context.uiCopy(
                            zh: '憑證設定',
                            en: 'Credential configuration',
                          ),
                        ),
                      ),
                      if (_credentialConfiguration != null &&
                          _credentialConfiguration!.claims.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<HostedIssuerClaimConfiguration>(
                          key: const Key('credential_claim'),
                          isExpanded: true,
                          initialValue: _claimConfiguration,
                          items: _credentialConfiguration!.claims
                              .map(
                                (claim) => DropdownMenuItem(
                                  value: claim,
                                  child: Text(claim.path),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (claim) =>
                              setState(() => _claimConfiguration = claim),
                          decoration: InputDecoration(
                            labelText: context.uiCopy(
                              zh: '必要條件',
                              en: 'Required claim',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('credential_claim_value'),
                          controller: _claimValueController,
                          decoration: InputDecoration(
                            labelText: context.uiCopy(
                              zh: '條件值',
                              en: 'Required value',
                            ),
                            helperText: context.uiCopy(
                              zh: '只支援 manifest 允許的 equals 條件。',
                              en: 'Only manifest-authorized equals predicates are supported.',
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _trustedIssuerController,
                      decoration: InputDecoration(
                        labelText: context.uiCopy(
                          zh: '可信簽發者 DID',
                          en: 'Trusted issuer DID',
                        ),
                        hintText: 'did:elix:org:…',
                      ),
                      validator: (value) {
                        if (_accessMode != 'public' &&
                            _memberCredentialPreset == 'custom' &&
                            (value == null ||
                                !value.trim().startsWith('did:'))) {
                          return context.uiCopy(
                            zh: '請輸入有效的 Issuer DID',
                            en: 'Enter a valid issuer DID',
                          );
                        }
                        if (_issuerManifest != null &&
                            value?.trim() != _issuerManifest!.organizationDid) {
                          return context.uiCopy(
                            zh: 'Issuer DID 必須與 manifest 相符',
                            en: 'Issuer DID must match the manifest',
                          );
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _accessMode == 'member_read'
                        ? context.uiCopy(
                            zh: 'Forum Host 可讀取內容；內容不會進入公開搜尋或 federation。',
                            en: 'The Forum Host can read content; it is excluded from public search and federation.',
                          )
                        : context.uiCopy(
                            zh: '內容仍公開；發文時需出示會員 VC。',
                            en: 'Content remains public; posting requires a membership VC.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: false,
                  leading: const Icon(Icons.lock_outline),
                  title: Text(
                    context.uiCopy(
                      zh: '端對端加密私密看板',
                      en: 'End-to-end encrypted board',
                    ),
                  ),
                  subtitle: Text(
                    context.uiCopy(
                      zh: '完成外部密碼學安全審查後才會開放。',
                      en: 'Available only after external cryptographic review.',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final description = _descriptionController.text.trim();
              final memberRequirement = _memberRequirement();
              final memberRead = _accessMode == 'member_read';
              final memberPost = _accessMode != 'public';
              final visibility = memberRead ? 'host_visible' : 'public';
              final federation = memberRead ? 'disabled' : 'enabled';
              final accessPolicy = {
                'version': 1,
                'discovery': memberRead ? 'credential_required' : 'public',
                'read': {'requirement': memberRead ? 'member' : 'public'},
                'post': {
                  'requirement': memberPost ? 'member' : 'posting_policy',
                },
                'moderate': {'requirement': 'board_moderator'},
                'requirements': memberPost ? {'member': memberRequirement} : {},
                'capability_ttl_seconds': 300,
                'content_visibility': visibility,
                'federation': federation,
              };
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'description': description.isEmpty ? null : description,
                if (_selectedForumHostId != null)
                  'forumHostId': _selectedForumHostId,
                // Included (possibly null) whenever the selector is shown so
                // edit mode can distinguish "cleared the gate" from "not
                // editable here".
                if (_showsPostingPolicy) 'minPostTier': _minPostTier,
                if (widget.requireForumHost)
                  'accessPolicyJson': jsonEncode(accessPolicy),
                if (widget.requireForumHost) 'contentVisibility': visibility,
                if (widget.requireForumHost)
                  'federationPolicyJson': jsonEncode({'mode': federation}),
              });
            }
          },
          child: Text(context.uiCopy(zh: '儲存', en: 'Save')),
        ),
      ],
    );
  }

  Future<void> _loadManifest() async {
    final uri = Uri.tryParse(_manifestUrlController.text.trim());
    if (uri == null) {
      setState(() => _manifestError = 'invalid_manifest_uri');
      return;
    }
    setState(() {
      _loadingManifest = true;
      _manifestError = null;
    });
    try {
      final manifest =
          await (widget.manifestLoader ?? HostedIssuerManifestClient()).load(
            uri,
          );
      if (!mounted) return;
      final first = manifest.configurations.firstOrNull;
      setState(() {
        _issuerManifest = manifest;
        _credentialConfiguration = first;
        _claimConfiguration = first?.claims.firstOrNull;
        _trustedIssuerController.text = manifest.organizationDid;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _manifestError = 'manifest_unavailable');
    } finally {
      if (mounted) setState(() => _loadingManifest = false);
    }
  }

  Object _policyValue(String raw) {
    final value = raw.trim();
    if (value == 'true') return true;
    if (value == 'false') return false;
    return int.tryParse(value) ?? value;
  }

  Map<String, Object?> _memberRequirement() {
    final issuerHost = Uri.parse(AppEnvironment.issuerBaseUrl).host;
    final systemIssuerDid = 'did:web:$issuerHost';
    if (_memberCredentialPreset == 'taiwan_citizenship') {
      return {
        'credential_type': 'TaiwanCitizenshipCredential',
        'trusted_issuers': [systemIssuerDid],
        'claims': [
          {'path': 'citizenshipVerified', 'op': 'equals', 'value': true},
        ],
        'holder_binding': 'required',
        'status': {'required': true, 'max_age_seconds': 300},
      };
    }
    if (_memberCredentialPreset == 'age_over_18') {
      return {
        'credential_type': 'AgeOver18Credential',
        'trusted_issuers': [systemIssuerDid],
        'claims': [
          {'path': 'ageOver18', 'op': 'equals', 'value': true},
        ],
        'holder_binding': 'required',
        'status': {'required': true, 'max_age_seconds': 300},
      };
    }

    final issuer = _trustedIssuerController.text.trim();
    final selectedConfiguration = _credentialConfiguration;
    final selectedClaim = _claimConfiguration;
    return {
      if (selectedConfiguration != null)
        'credential_configuration_id': selectedConfiguration.id,
      'credential_type':
          selectedConfiguration?.credentialType ??
          'PoliticalPartyMembershipCredential',
      'trusted_issuers': [issuer],
      'claims': [
        {
          'path': selectedClaim?.path ?? 'membership',
          'op': 'equals',
          'value': _policyValue(_claimValueController.text),
        },
      ],
      'holder_binding': 'required',
      'status': {'required': true, 'max_age_seconds': 300},
    };
  }
}
