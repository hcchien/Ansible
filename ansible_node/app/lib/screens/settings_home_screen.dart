import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'credential_admin_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'sync_settings_screen.dart';
import 'wallet_screen.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({
    super.key,
    required this.db,
    required this.did,
    this.onClearIdentity,
  });

  final AppDatabase db;
  final String did;
  final VoidCallback? onClearIdentity;

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: 'SETTINGS',
      leadingLabel: '',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text(
          '完成',
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.accentSoft,
                    border: Border.all(color: AnsibleDesign.accent, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'T',
                    style: TextStyle(
                      fontSize: 22,
                      color: AnsibleDesign.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tris',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '本機 DID · ${_shortDid(did)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9.5,
                          letterSpacing: 1,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: const Text(
                    '編輯',
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SettingsSection(
            label: '身分與裝置 · IDENTITY',
            children: [
              FutureBuilder<List<WalletCredential>>(
                future: DriftWalletRepository(db).listCredentials(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return AnsibleSettingsRow(
                    glyph: '◎',
                    label: '錢包',
                    en: 'WALLET',
                    sub: count == 0 ? '尚無憑證' : '$count 個憑證',
                    value: count == 0 ? '空' : '$count',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WalletScreen(
                            holderDid: did,
                            repository: DriftWalletRepository(db),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              AnsibleSettingsRow(
                glyph: '↔',
                label: '同步',
                en: 'SYNC',
                sub: '3 台裝置 · 點對點',
                value: '已同步',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SyncSettingsScreen(db: db),
                    ),
                  );
                },
              ),
              AnsibleSettingsRow(
                glyph: '□',
                label: '存取與審計',
                en: 'ADMIN',
                sub: '誰看見了哪一個我',
                value: '0 可疑',
                last: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CredentialAdminScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          _SettingsSection(
            label: '日常 · DAILY',
            children: [
              AnsibleSettingsRow(
                glyph: '◐',
                label: '收信',
                en: 'INBOX',
                sub: '圈內回覆、新成員、同步',
                value: '0',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InboxScreen()),
                  );
                },
              ),
              const AnsibleSettingsRow(
                glyph: '◇',
                label: '通知',
                en: 'NOTIFICATIONS',
                sub: '決定哪些事會打擾你',
                value: '輕',
              ),
              const AnsibleSettingsRow(
                glyph: 'A',
                label: '閱讀偏好',
                en: 'READING',
                sub: '字級、行距、主題',
                value: '松茸 · 大',
                last: true,
              ),
            ],
          ),
          _SettingsSection(
            label: '邊界 · BOUNDARIES',
            children: const [
              AnsibleSettingsRow(
                glyph: '●',
                label: '鎖定',
                en: 'LOCK',
                sub: '把 app 變成空白封面',
                value: '關閉',
              ),
              AnsibleSettingsRow(
                glyph: '⌷',
                label: '備份與還原',
                en: 'RECOVERY',
                sub: 'passphrase、新裝置遷移',
                value: '未設',
              ),
              AnsibleSettingsRow(
                glyph: '⊘',
                label: '封鎖名單',
                en: 'BLOCKED',
                sub: '你看不到，他們也看不到你',
                value: '0',
                last: true,
              ),
            ],
          ),
          _SettingsSection(
            label: '關於 · ABOUT',
            children: [
              const AnsibleSettingsRow(
                glyph: 'i',
                label: '關於 Ansible',
                en: 'ABOUT',
                sub: '信號越過星際的距離',
              ),
              const AnsibleSettingsRow(glyph: '?', label: '使用手冊', en: 'MANUAL'),
              AnsibleSettingsRow(
                glyph: '!',
                label: '登出此裝置',
                en: 'SIGN OUT',
                sub: '保留資料；下次需要 passkey',
                danger: true,
                last: true,
                onTap: () => _confirmClearIdentity(context),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 20, 22, 32),
            child: Text(
              'ANSIBLE · v0.7.2 · LOCAL-FIRST',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9.5,
                letterSpacing: 1.2,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearIdentity(BuildContext context) async {
    if (onClearIdentity == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除本機身份'),
        content: const Text('這會停止使用目前本機身份。你的本地資料仍留在裝置上。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) onClearIdentity!();
  }

  static String _shortDid(String did) {
    if (did.length <= 20) return did;
    return '${did.substring(0, 14)}...${did.substring(did.length - 4)}';
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          label,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        ),
        AnsibleRuleGroup(children: children),
      ],
    );
  }
}
