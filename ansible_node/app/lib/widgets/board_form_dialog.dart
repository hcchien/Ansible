import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/hosted_issuer_manifest.dart';
import '../services/board_policy_draft.dart';

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
  final Map<String, Object?> initialPostingPolicy;
  final Map<String, Object?> initialAccessPolicy;
  final bool policyOnly;
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
    this.initialPostingPolicy = const {},
    this.initialAccessPolicy = const {},
    this.policyOnly = false,
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

  String _memberCredentialPreset = 'taiwan_citizenship';
  BoardAudienceMode _audienceMode = BoardAudienceMode.public;
  HostedIssuerManifest? _issuerManifest;
  HostedIssuerCredentialConfiguration? _credentialConfiguration;
  HostedIssuerClaimConfiguration? _claimConfiguration;
  Map<String, Object?>? _initialCustomRequirement;
  late final BoardAudienceMode _initialAudienceMode;
  String? _manifestError;
  var _loadingManifest = false;
  PollCreationRole _pollCreationRole = PollCreationRole.posters;

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
    final initialDraft = BoardPolicyDraft.fromPolicies(
      postingPolicy: {
        ...widget.initialPostingPolicy,
        if (widget.initialMinPostTier != null)
          'min_post_tier': widget.initialMinPostTier,
      },
      accessPolicy: widget.initialAccessPolicy,
    );
    _initialAudienceMode = initialDraft.mode;
    _pollCreationRole = PollCreationRole.values.firstWhere(
      (role) => role.name == widget.initialPostingPolicy['poll_creation'],
      orElse: () => PollCreationRole.posters,
    );
    _initialCustomRequirement = initialDraft.customRequirement;
    final initialIssuers = _initialCustomRequirement?['trusted_issuers'];
    if (initialIssuers is List && initialIssuers.firstOrNull is String) {
      _trustedIssuerController.text = initialIssuers.first as String;
    }
    _applyAudienceMode(initialDraft.mode);
  }

  bool get _showsPostingPolicy =>
      widget.requireForumHost || widget.showPostingPolicy || widget.policyOnly;

  void _applyAudienceMode(BoardAudienceMode mode) {
    _audienceMode = mode;
    _memberCredentialPreset = switch (mode) {
      BoardAudienceMode.taiwanCitizenPost => 'taiwan_citizenship',
      BoardAudienceMode.adultPost => 'age_over_18',
      BoardAudienceMode.memberPost ||
      BoardAudienceMode.memberRead => 'organization_membership',
      BoardAudienceMode.customPost || BoardAudienceMode.customRead => 'custom',
      _ => _memberCredentialPreset,
    };
  }

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
        widget.policyOnly
            ? context.uiCopy(zh: '看板存取政策', en: 'Board access policy')
            : widget.initialTitle == null
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
              if (!widget.policyOnly)
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
                      return context.uiCopy(
                        zh: '請輸入標題',
                        en: 'Title is required',
                      );
                    }
                    return null;
                  },
                ),
              if (!widget.policyOnly) const SizedBox(height: 16),
              if (!widget.policyOnly)
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
                DropdownButtonFormField<BoardAudienceMode>(
                  key: const Key('board_audience_mode'),
                  initialValue: _audienceMode,
                  items: [
                    DropdownMenuItem(
                      value: BoardAudienceMode.public,
                      child: Text(
                        context.uiCopy(
                          zh: '所有人都能閱讀與發文',
                          en: 'Everyone can read and post',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.verifiedHumanPost,
                      child: Text(
                        context.uiCopy(
                          zh: '所有人可閱讀，已驗證真人才能發文',
                          en: 'Public read, verified humans can post',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.taiwanCitizenPost,
                      child: Text(
                        context.uiCopy(
                          zh: '所有人可閱讀，台灣公民才能發文',
                          en: 'Public read, Taiwan citizens can post',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.adultPost,
                      child: Text(
                        context.uiCopy(
                          zh: '所有人可閱讀，年滿 18 歲才能發文',
                          en: 'Public read, adults can post',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.memberPost,
                      child: Text(
                        context.uiCopy(
                          zh: '所有人可閱讀，組織會員才能發文',
                          en: 'Public read, organization members can post',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.memberRead,
                      child: Text(
                        context.uiCopy(
                          zh: '只有組織會員能找到與閱讀',
                          en: 'Organization members can discover and read',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.customPost,
                      child: Text(
                        context.uiCopy(
                          zh: '其他資格才能發文（進階）',
                          en: 'Other credential for posting (advanced)',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: BoardAudienceMode.customRead,
                      child: Text(
                        context.uiCopy(
                          zh: '其他資格才能找到與閱讀（進階）',
                          en: 'Other credential for reading (advanced)',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _applyAudienceMode(value ?? BoardAudienceMode.public),
                  ),
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '這個看板給誰使用？',
                      en: 'Who is this board for?',
                    ),
                    helperText: context.uiCopy(
                      zh: '資格只適用於這個看板，不會提高全域信任等級。',
                      en: 'Eligibility applies only to this board and never changes global reputation.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PollCreationRole>(
                  key: const Key('board_poll_creation_role'),
                  initialValue: _pollCreationRole,
                  items: const [
                    DropdownMenuItem(
                      value: PollCreationRole.posters,
                      child: Text('可發言者都能建立投票'),
                    ),
                    DropdownMenuItem(
                      value: PollCreationRole.moderators,
                      child: Text('僅版主能建立投票'),
                    ),
                    DropdownMenuItem(
                      value: PollCreationRole.owners,
                      child: Text('僅看板擁有者能建立投票'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _pollCreationRole = value ?? PollCreationRole.posters,
                  ),
                  decoration: const InputDecoration(labelText: '誰可以建立投票？'),
                ),
                if (_memberCredentialPreset == 'custom') ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    key: const Key('advanced_credential_settings'),
                    initiallyExpanded: true,
                    title: Text(
                      context.uiCopy(
                        zh: '選擇 Hosted Issuer 與資格',
                        en: 'Choose Hosted Issuer and credential',
                      ),
                    ),
                    subtitle: Text(
                      context.uiCopy(
                        zh: '技術欄位只在進階設定中顯示',
                        en: 'Technical fields stay inside advanced settings',
                      ),
                    ),
                    children: [
                      if (_initialCustomRequirement != null &&
                          _issuerManifest == null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.verified_outlined),
                          title: Text(
                            (_initialCustomRequirement!['credential_type'] ??
                                    context.uiCopy(
                                      zh: '目前憑證',
                                      en: 'Current credential',
                                    ))
                                .toString(),
                          ),
                          subtitle: Text(
                            context.uiCopy(
                              zh: '目前政策會原樣保留；載入新的 Issuer manifest 才會取代。',
                              en: 'The current requirement is preserved unchanged until a new Issuer manifest is loaded.',
                            ),
                          ),
                        ),
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
                          errorText: _manifestError == null
                              ? null
                              : _manifestErrorText(context, _manifestError!),
                        ),
                        validator: (_) {
                          if (_issuerManifest == null &&
                              _initialCustomRequirement == null) {
                            return context.uiCopy(
                              zh: '請先載入 Hosted Issuer manifest',
                              en: 'Load a Hosted Issuer manifest first',
                            );
                          }
                          return null;
                        },
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
                          DropdownButtonFormField<
                            HostedIssuerClaimConfiguration
                          >(
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
                            onChanged: (claim) => setState(() {
                              _claimConfiguration = claim;
                              _claimValueController.text =
                                  claim?.allowedValues.firstOrNull
                                      ?.toString() ??
                                  (claim?.valueType == 'boolean' ? 'true' : '');
                            }),
                            decoration: InputDecoration(
                              labelText: context.uiCopy(
                                zh: '必要條件',
                                en: 'Required claim',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildClaimValueField(context),
                        ],
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _trustedIssuerController,
                        readOnly: _issuerManifest != null,
                        decoration: InputDecoration(
                          labelText: context.uiCopy(
                            zh: '可信簽發者 DID',
                            en: 'Trusted issuer DID',
                          ),
                          hintText: 'did:elix:org:…',
                        ),
                        validator: (value) {
                          if (_memberCredentialPreset == 'custom' &&
                              (value == null ||
                                  !value.trim().startsWith('did:'))) {
                            return context.uiCopy(
                              zh: '請輸入有效的 Issuer DID',
                              en: 'Enter a valid issuer DID',
                            );
                          }
                          if (_issuerManifest != null &&
                              value?.trim() !=
                                  _issuerManifest!.organizationDid) {
                            return context.uiCopy(
                              zh: 'Issuer DID 必須與 manifest 相符',
                              en: 'Issuer DID must match the manifest',
                            );
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  key: const Key('board_policy_summary'),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.uiCopy(
                            zh: '儲存前確認',
                            en: 'Review before saving',
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(_localizedPolicySummary(context)),
                        const SizedBox(height: 8),
                        Text(
                          context.uiCopy(
                            zh: '只會驗證決策所需的最少條件；完整憑證不會交給 Forum Host。',
                            en: 'Only the minimum claim needed for the decision is verified; the Forum Host never receives the full credential.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                ExpansionTile(
                  key: const Key('board_policy_technical_preview'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    context.uiCopy(
                      zh: '進階技術資訊',
                      en: 'Advanced technical details',
                    ),
                  ),
                  subtitle: Text(
                    context.uiCopy(
                      zh: '唯讀 policy JSON',
                      en: 'Read-only policy JSON',
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        canonicalPolicyJson(
                          _currentDraft().accessPolicy(
                            systemIssuerDid: _systemIssuerDid,
                          ),
                        ),
                        key: const Key('board_policy_json_preview'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
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
              final draft = _currentDraft();
              final accessPolicy = draft.accessPolicy(
                systemIssuerDid: _systemIssuerDid,
              );
              final visibility = draft.contentVisibility;
              final federation = draft.federationMode;
              Navigator.pop(context, {
                if (!widget.policyOnly) 'title': _titleController.text.trim(),
                if (!widget.policyOnly)
                  'description': description.isEmpty ? null : description,
                if (_selectedForumHostId != null)
                  'forumHostId': _selectedForumHostId,
                // Included (possibly null) whenever the selector is shown so
                // edit mode can distinguish "cleared the gate" from "not
                // editable here".
                if (_showsPostingPolicy)
                  'minPostTier': draft.effectiveMinPostTier,
                if (_showsPostingPolicy)
                  'postingPolicyJson': jsonEncode(draft.postingPolicy),
                if (widget.requireForumHost || widget.policyOnly)
                  'accessPolicyJson': jsonEncode(accessPolicy),
                if (widget.requireForumHost || widget.policyOnly)
                  'contentVisibility': visibility,
                if (widget.requireForumHost || widget.policyOnly)
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
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
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

  String _manifestErrorText(BuildContext context, String code) {
    return switch (code) {
      'invalid_manifest_uri' => context.uiCopy(
        zh: '請輸入有效的 HTTPS manifest URL',
        en: 'Enter a valid HTTPS manifest URL',
      ),
      'manifest_unavailable' => context.uiCopy(
        zh: '無法載入 Issuer manifest，請檢查網址與網路',
        en: 'Could not load the Issuer manifest. Check the URL and network.',
      ),
      _ => context.uiCopy(
        zh: 'Issuer manifest 格式不受支援',
        en: 'The Issuer manifest format is not supported.',
      ),
    };
  }

  Object _policyValue(String raw) {
    final value = raw.trim();
    return switch (_claimConfiguration?.valueType) {
      'boolean' => value == 'true',
      'integer' => int.parse(value),
      _ => value,
    };
  }

  Widget _buildClaimValueField(BuildContext context) {
    final claim = _claimConfiguration;
    final allowedValues = claim?.allowedValues ?? const [];
    if (allowedValues.isNotEmpty) {
      final current =
          allowedValues
              .map((value) => value.toString())
              .contains(_claimValueController.text)
          ? _claimValueController.text
          : allowedValues.first.toString();
      _claimValueController.text = current;
      return DropdownButtonFormField<String>(
        key: const Key('credential_claim_value'),
        initialValue: current,
        items: allowedValues
            .map(
              (value) => DropdownMenuItem(
                value: value.toString(),
                child: Text(value.toString()),
              ),
            )
            .toList(growable: false),
        onChanged: (value) => _claimValueController.text = value ?? current,
        decoration: InputDecoration(
          labelText: context.uiCopy(zh: '條件值', en: 'Required value'),
        ),
      );
    }
    if (claim?.valueType == 'boolean') {
      final current = _claimValueController.text == 'false' ? 'false' : 'true';
      _claimValueController.text = current;
      return DropdownButtonFormField<String>(
        key: const Key('credential_claim_value'),
        initialValue: current,
        items: [
          DropdownMenuItem(
            value: 'true',
            child: Text(context.uiCopy(zh: '是', en: 'Yes')),
          ),
          DropdownMenuItem(
            value: 'false',
            child: Text(context.uiCopy(zh: '否', en: 'No')),
          ),
        ],
        onChanged: (value) => _claimValueController.text = value ?? 'true',
        decoration: InputDecoration(
          labelText: context.uiCopy(zh: '必要條件', en: 'Required condition'),
        ),
      );
    }
    return TextFormField(
      key: const Key('credential_claim_value'),
      controller: _claimValueController,
      keyboardType: claim?.valueType == 'integer'
          ? TextInputType.number
          : TextInputType.text,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return context.uiCopy(zh: '請輸入條件值', en: 'Enter a required value');
        }
        if (claim?.valueType == 'integer' &&
            int.tryParse(value.trim()) == null) {
          return context.uiCopy(zh: '請輸入整數', en: 'Enter an integer');
        }
        if (claim?.valueType == 'integer') {
          final integer = int.parse(value.trim());
          if (integer < 0 || integer > 1000000) {
            return context.uiCopy(
              zh: '整數必須介於 0 與 1,000,000',
              en: 'Enter an integer from 0 to 1,000,000',
            );
          }
        }
        if (claim?.valueType != 'integer' && value.trim().length > 128) {
          return context.uiCopy(
            zh: '條件值最多 128 個字元',
            en: 'The value must be at most 128 characters',
          );
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: context.uiCopy(zh: '條件值', en: 'Required value'),
        helperText: context.uiCopy(
          zh: '值的型別由 Issuer manifest 決定，不會自動猜測。',
          en: 'The Issuer manifest defines the value type; the app does not guess.',
        ),
      ),
    );
  }

  String get _systemIssuerDid {
    final issuerHost = Uri.parse(AppEnvironment.issuerBaseUrl).host;
    return 'did:web:$issuerHost';
  }

  BoardPolicyDraft _currentDraft() => BoardPolicyDraft(
    mode: _audienceMode,
    pollCreationRole: _pollCreationRole,
    customRequirement:
        _audienceMode == _initialAudienceMode &&
            _issuerManifest == null &&
            _initialCustomRequirement != null
        ? _initialCustomRequirement
        : _memberCredentialPreset == 'custom'
        ? _memberRequirement()
        : null,
  );

  String _localizedPolicySummary(BuildContext context) {
    return switch (_audienceMode) {
      BoardAudienceMode.public => context.uiCopy(
        zh: '所有人都能找到、閱讀與發文。內容公開，並允許 federation。',
        en: 'Everyone can discover, read, and post. Content is public and federation is enabled.',
      ),
      BoardAudienceMode.verifiedHumanPost => context.uiCopy(
        zh: '所有人可閱讀；只有已驗證真人可發文。內容公開，並允許 federation。',
        en: 'Everyone can read; posting requires verified-human status. Content is public and federation is enabled.',
      ),
      BoardAudienceMode.taiwanCitizenPost => context.uiCopy(
        zh: '所有人可閱讀；發文只驗證「台灣公民資格有效」。',
        en: 'Everyone can read; posting verifies only that Taiwan citizenship eligibility is valid.',
      ),
      BoardAudienceMode.adultPost => context.uiCopy(
        zh: '所有人可閱讀；發文只驗證「已年滿 18 歲」。',
        en: 'Everyone can read; posting verifies only that the person is at least 18.',
      ),
      BoardAudienceMode.memberPost => context.uiCopy(
        zh: '所有人可閱讀；發文只驗證「組織會員資格有效」。',
        en: 'Everyone can read; posting verifies only active organization membership.',
      ),
      BoardAudienceMode.memberRead => context.uiCopy(
        zh: '只有有效組織會員能找到、閱讀與發文。Forum Host 可讀內容；公開搜尋與 federation 關閉。',
        en: 'Only active organization members can discover, read, and post. The Forum Host can read content; public search and federation are disabled.',
      ),
      BoardAudienceMode.customPost => context.uiCopy(
        zh: '所有人可閱讀；發文需要所選憑證的最少條件。',
        en: 'Everyone can read; posting requires the selected credential’s minimum claim.',
      ),
      BoardAudienceMode.customRead => context.uiCopy(
        zh: '只有符合所選憑證條件者能找到、閱讀與發文；公開搜尋與 federation 關閉。',
        en: 'Only people satisfying the selected credential claim can discover, read, and post; public search and federation are disabled.',
      ),
    };
  }

  Map<String, Object?> _memberRequirement() {
    final systemIssuerDid = _systemIssuerDid;
    if (_memberCredentialPreset == 'taiwan_citizenship') {
      return {
        'credential_type': 'NationalityCredential',
        'trusted_issuers': [systemIssuerDid],
        'claims': [
          {'path': 'nationalityVerified', 'op': 'equals', 'value': true},
          {'path': 'nationality', 'op': 'equals', 'value': 'TWN'},
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
    if (_memberCredentialPreset == 'organization_membership') {
      return {
        'credential_type': 'PoliticalPartyMembershipCredential',
        'trusted_issuers': [systemIssuerDid],
        'claims': [
          {'path': 'membership', 'op': 'equals', 'value': true},
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
