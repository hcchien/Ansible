import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/credential_payload_codec.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class CredentialDetailScreen extends StatefulWidget {
  const CredentialDetailScreen({
    super.key,
    required this.credential,
    required this.repository,
    this.payloadCodec = const SecureCredentialPayloadCodec(),
  });

  final WalletCredential credential;
  final WalletRepository repository;
  final SecureCredentialPayloadCodec payloadCodec;

  @override
  State<CredentialDetailScreen> createState() => _CredentialDetailScreenState();
}

class _CredentialDetailScreenState extends State<CredentialDetailScreen> {
  late final Future<_CredentialDetail> _detail = _load();

  Future<_CredentialDetail> _load() async {
    TrisAuraCredential? credential;
    Object? payloadError;
    try {
      final encoded = await widget.repository.getEncryptedPayload(
        widget.credential.credentialId,
      );
      if (encoded == null) {
        throw StateError('Credential payload is unavailable.');
      }
      final payload = await widget.payloadCodec.decode(encoded);
      credential = TrisAuraCredential.fromJson(payload);
    } catch (error) {
      // Metadata remains useful and privacy-safe when an older installation
      // retained the Wallet row but its non-exportable secure payload is no
      // longer available (for example after reinstalling the app).
      payloadError = error;
    }
    final presentations = await widget.repository.listPresentations(
      widget.credential.credentialId,
    );
    return _CredentialDetail(
      credential: credential,
      presentations: presentations,
      payloadError: payloadError,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '憑證詳情', en: 'CREDENTIAL'),
      leadingLabel: context.uiCopy(zh: '← 皮夾', en: '← Wallet'),
      child: FutureBuilder<_CredentialDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _DetailMessage(
              icon: Icons.lock_outline,
              title: context.uiCopy(zh: '無法讀取憑證', en: 'Credential unavailable'),
              body: context.uiCopy(
                zh: '本機加密內容無法解鎖。憑證沒有傳送到其他服務。',
                en: 'The local encrypted payload could not be unlocked. Nothing was sent to another service.',
              ),
            );
          }
          final detail = snapshot.data!;
          final vc = detail.credential;
          final proofType = vc?.proof?['type']?.toString();
          final proofSuite = vc?.proof?['cryptosuite']?.toString();
          final visibleClaims =
              vc?.claims.entries
                  .where((entry) => entry.key != 'id')
                  .toList(growable: false) ??
              _metadataClaims(widget.credential);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
            children: [
              _CredentialHeader(credential: widget.credential),
              if (detail.payloadError != null) ...[
                const SizedBox(height: 14),
                _DetailMessage(
                  icon: Icons.lock_clock_outlined,
                  title: context.uiCopy(
                    zh: '僅能讀取憑證摘要',
                    en: 'Credential summary only',
                  ),
                  body: context.uiCopy(
                    zh: '這份憑證來自較早的安裝，本機安全儲存區已沒有完整內容。摘要仍可查看；需要出示完整憑證時請重新完成驗證。',
                    en: 'This credential belongs to an earlier installation and its complete payload is no longer in secure storage. You can still inspect the summary; verify again before presenting the full credential.',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _Section(
                title: context.uiCopy(zh: '憑證資料', en: 'Credential'),
                children: [
                  _Field(
                    label: context.uiCopy(zh: '類型', en: 'Type'),
                    value:
                        vc?.types
                            .where((type) => type != 'VerifiableCredential')
                            .join(', ') ??
                        widget.credential.credentialType,
                  ),
                  _Field(
                    label: context.uiCopy(zh: '簽發者', en: 'Issuer'),
                    value: vc?.issuerDid ?? widget.credential.issuerDid,
                  ),
                  _Field(
                    label: context.uiCopy(zh: '持有人', en: 'Holder'),
                    value: _shortDid(
                      vc?.holderDid ?? widget.credential.holderDid,
                    ),
                  ),
                  _Field(
                    label: context.uiCopy(zh: '有效期間', en: 'Validity'),
                    value:
                        '${_date(vc?.validFrom ?? widget.credential.validFrom)} — '
                        '${_date(vc?.validUntil ?? widget.credential.validUntil)}',
                  ),
                  _Field(
                    label: context.uiCopy(zh: '憑證 ID', en: 'Credential ID'),
                    value: vc?.id ?? widget.credential.credentialId,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: context.uiCopy(zh: '可揭露聲明', en: 'Disclosable claims'),
                children: visibleClaims.isEmpty
                    ? [
                        _Field(
                          label: context.uiCopy(zh: '聲明', en: 'Claims'),
                          value: context.uiCopy(
                            zh: '此憑證沒有額外公開聲明',
                            en: 'This credential has no additional public claims',
                          ),
                        ),
                      ]
                    : visibleClaims
                          .map(
                            (entry) => _Field(
                              label: _claimLabel(context, entry.key),
                              value: _claimValue(entry.value),
                            ),
                          )
                          .toList(),
              ),
              const SizedBox(height: 14),
              _Section(
                title: context.uiCopy(zh: '驗證資訊', en: 'Verification'),
                children: [
                  _Field(
                    label: context.uiCopy(zh: '本機檢查', en: 'Local checks'),
                    value: detail.payloadError == null
                        ? context.uiCopy(
                            zh: '結構、期限與隱私欄位檢查通過',
                            en: 'Structure, validity, and privacy-field checks passed',
                          )
                        : context.uiCopy(
                            zh: '僅檢查 Wallet 摘要與有效期限',
                            en: 'Only Wallet metadata and validity were checked',
                          ),
                    icon: detail.payloadError == null
                        ? Icons.verified_outlined
                        : Icons.info_outline,
                  ),
                  _Field(
                    label: context.uiCopy(zh: '簽章證明', en: 'Proof'),
                    value: detail.payloadError != null
                        ? context.uiCopy(
                            zh: '完整內容不在本機安全儲存區',
                            en: 'Full payload is unavailable in secure storage',
                          )
                        : [
                            if (proofType != null) proofType,
                            if (proofSuite != null) proofSuite,
                          ].join(' · ').isEmpty
                        ? context.uiCopy(zh: '未提供', en: 'Not provided')
                        : [
                            if (proofType != null) proofType,
                            if (proofSuite != null) proofSuite,
                          ].join(' · '),
                  ),
                  _Field(
                    label: context.uiCopy(zh: '出示紀錄', en: 'Presentations'),
                    value: context.uiCopy(
                      zh: '${detail.presentations.length} 次',
                      en: '${detail.presentations.length} presentations',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _DetailMessage(
                icon: Icons.privacy_tip_outlined,
                title: context.uiCopy(zh: '最小揭露', en: 'Minimum disclosure'),
                body: context.uiCopy(
                  zh: '這個畫面只讀取本機 Wallet。護照號碼、身分證字號、姓名與出生日期不會顯示，也不會包含在可出示的憑證中。',
                  en: 'This screen reads only the local Wallet. Passport numbers, national IDs, legal names, and birth dates are neither shown nor included in presentable credentials.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CredentialDetail {
  const _CredentialDetail({
    required this.credential,
    required this.presentations,
    this.payloadError,
  });

  final TrisAuraCredential? credential;
  final List<WalletPresentation> presentations;
  final Object? payloadError;
}

List<MapEntry<String, Object?>> _metadataClaims(WalletCredential credential) {
  return switch (credential.credentialType) {
    'NationalityCredential' => const [MapEntry('nationalityVerified', true)],
    'AgeOver18Credential' => const [MapEntry('ageOver18', true)],
    _ => const [],
  };
}

class _CredentialHeader extends StatelessWidget {
  const _CredentialHeader({required this.credential});

  final WalletCredential credential;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AnsibleDesign.spore.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.verified_user_outlined,
            color: AnsibleDesign.spore,
            size: 30,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizedCredentialName(context, credential),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                credential.status == WalletCredentialStatus.active
                    ? context.uiCopy(zh: '有效', en: 'Active')
                    : credential.status.name,
                style: const TextStyle(
                  color: AnsibleDesign.spore,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              letterSpacing: 1.3,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AnsibleDesign.spore),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(
                color: AnsibleDesign.inkMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: AnsibleDesign.ink,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AnsibleDesign.inkMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AnsibleDesign.inkMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
}

String _shortDid(String value) {
  if (value.length <= 28) return value;
  return '${value.substring(0, 16)}…${value.substring(value.length - 8)}';
}

String _claimValue(Object? value) {
  if (value is String || value is num || value is bool) return value.toString();
  return const JsonEncoder.withIndent('  ').convert(value);
}

String _claimLabel(BuildContext context, String key) {
  return switch (key) {
    'nationality' => context.uiCopy(zh: '國籍', en: 'Nationality'),
    'ageOver18' ||
    'over18' => context.uiCopy(zh: '年滿 18 歲', en: 'Age 18 or older'),
    'humanVerified' ||
    'verifiedHuman' => context.uiCopy(zh: '真人驗證', en: 'Verified human'),
    'humanAssurance' => context.uiCopy(zh: '真人保證等級', en: 'Human assurance'),
    'uniquenessAssurance' => context.uiCopy(
      zh: '唯一性保證',
      en: 'Uniqueness assurance',
    ),
    'verificationMethodClass' => context.uiCopy(
      zh: '驗證方式類別',
      en: 'Verification method class',
    ),
    _ => key,
  };
}

String _localizedCredentialName(
  BuildContext context,
  WalletCredential credential,
) {
  return switch (credential.credentialType) {
    'NationalityCredential' => context.uiCopy(
      zh: '國籍驗證',
      en: 'Verified Nationality',
    ),
    'AgeOver18Credential' => context.uiCopy(
      zh: '年滿 18 歲',
      en: 'Age 18 or Older',
    ),
    'TrisAuraHumanityCredential' => context.uiCopy(
      zh: '真人驗證',
      en: 'Verified Human',
    ),
    _ => credential.displayName,
  };
}
