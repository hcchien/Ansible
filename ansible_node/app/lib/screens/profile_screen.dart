import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.did,
    this.displayName,
    this.handle,
    this.publicKeyLabel,
    this.bio,
  });

  final String? did;
  final String? displayName;
  final String? handle;
  final String? publicKeyLabel;
  final String? bio;

  @override
  Widget build(BuildContext context) {
    final name =
        _blankToNull(displayName) ??
        context.uiCopy(zh: '尚未設定公開身分', en: 'Public identity not set');
    final handleLabel =
        _blankToNull(handle) ??
        context.uiCopy(zh: '尚未設定 handle', en: 'Handle not set');
    final keyLabel =
        _blankToNull(publicKeyLabel) ??
        (did == null
            ? context.uiCopy(zh: 'pk · 未設定', en: 'pk · not set')
            : 'did · ${_shortDid(did!)}');
    final bioText =
        _blankToNull(bio) ??
        context.uiCopy(zh: '尚未設定公開簡介。', en: 'Public bio is not set.');

    return AnsibleScreenScaffold(
      title: '',
      leadingLabel: context.uiCopy(zh: '← 討論串', en: '← Discussion'),
      trailing: IconButton(
        onPressed: () {},
        icon: const Icon(Icons.more_horiz),
        tooltip: context.uiCopy(zh: '更多', en: 'More'),
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnsibleMonoLabel(
                  context.uiCopy(
                    zh: '公開身分 · PUBLIC HANDLE',
                    en: 'PUBLIC HANDLE',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AnsibleDesign.paperDeep,
                        border: Border.all(
                          color: AnsibleDesign.rule,
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        name.characters.first,
                        style: const TextStyle(
                          fontSize: 26,
                          color: AnsibleDesign.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: AnsibleDesign.ink,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            handleLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AnsibleDesign.inkMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            keyLabel,
                            style: TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 9,
                              letterSpacing: 1.1,
                              color: AnsibleDesign.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  bioText,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.7,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _ProfileMeta(
                      context.uiCopy(
                        zh: '公開身分尚未發布',
                        en: 'Public identity not published',
                      ),
                    ),
                    _ProfileMeta(
                      context.uiCopy(zh: '0 個共同的圈', en: '0 mutual circles'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: null,
                        child: Text(
                          context.uiCopy(
                            zh: '追蹤公開發布',
                            en: 'Follow Public Posts',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: null,
                      child: Text(context.uiCopy(zh: '邀請進圈', en: 'Invite')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnsibleDesign.paperDeep.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.uiCopy(
                        zh: '公開身分尚未設定，因此目前沒有可顯示的公開資料。',
                        en: 'Public identity is not set, so there is no public profile data to show yet.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnsibleMonoLabel(
            context.uiCopy(zh: '公開發布 · PUBLIC · 0', en: 'PUBLIC POSTS · 0'),
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          ),
          AnsibleRuleGroup(
            children: [
              _EmptyProfileRow(
                context.uiCopy(zh: '目前沒有公開發布', en: 'No public posts yet'),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String _shortDid(String did) {
    if (did.length <= 18) return did;
    return '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
  }
}

class _EmptyProfileRow extends StatelessWidget {
  const _EmptyProfileRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  const _ProfileMeta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 11,
            letterSpacing: 1,
            color: AnsibleDesign.inkFaint,
          ),
        ),
      ],
    );
  }
}
