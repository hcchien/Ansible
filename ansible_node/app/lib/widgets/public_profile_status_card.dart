import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../screens/edit_profile_screen.dart';
import '../services/discovery_client.dart';

/// Reports observed public-index state, never inferred publication success.
class PublicProfileStatusCard extends StatefulWidget {
  const PublicProfileStatusCard({
    super.key,
    required this.db,
    required this.did,
    this.client,
    this.allowEdit = true,
    this.onDismiss,
  });

  final AppDatabase db;
  final String did;
  final DiscoveryClient? client;
  final bool allowEdit;
  final VoidCallback? onDismiss;

  @override
  State<PublicProfileStatusCard> createState() =>
      _PublicProfileStatusCardState();
}

class _PublicProfileStatusCardState extends State<PublicProfileStatusCard> {
  late DiscoveryClient _client;
  bool _checking = true;
  bool _failed = false;
  ContactRecord? _local;
  DiscoveredActor? _public;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _makeClient();
    _check();
  }

  void _makeClient() {
    _client =
        widget.client ??
        DiscoveryClient(
          appViewBaseUrl: AppEnvironment.appViewBaseUrl,
          relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
        );
  }

  @override
  void didUpdateWidget(covariant PublicProfileStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      if (oldWidget.client == null) _client.close();
      _makeClient();
    }
    if (oldWidget.did != widget.did ||
        oldWidget.db != widget.db ||
        oldWidget.client != widget.client) {
      _check();
    }
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _check() async {
    final request = ++_request;
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final local = await DriftContactRepository(
        widget.db,
      ).contactForDid(widget.did);
      final published = await _client.publicProfile(widget.did);
      if (!mounted || request != _request) return;
      setState(() {
        _local = local;
        _public = published;
        _checking = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _checking = false;
      });
    }
  }

  String _value(String? value) => value?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final hasLocal =
        _value(_local?.handle).isNotEmpty ||
        _value(_local?.displayName).isNotEmpty;
    final indexed =
        _public != null &&
        (_value(_public?.handle).isNotEmpty ||
            _value(_public?.displayName).isNotEmpty);
    final changed =
        indexed &&
        _local != null &&
        (_value(_local?.handle) != _value(_public?.handle) ||
            _value(_local?.displayName) != _value(_public?.displayName) ||
            _value(_local?.avatarUrl) != _value(_public?.avatarUrl));
    final title = _checking
        ? context.uiCopy(zh: '正在確認公開狀態…', en: 'Checking public profile…')
        : _failed
        ? context.uiCopy(zh: '暫時無法確認公開狀態', en: 'Could not check public profile')
        : changed
        ? context.uiCopy(
            zh: '已公開，本機有待發布的變更',
            en: 'Public · local changes pending',
          )
        : indexed
        ? context.uiCopy(zh: '已可被搜尋', en: 'People can find your profile')
        : hasLocal
        ? context.uiCopy(zh: '尚未找到這份公開檔案', en: 'Public profile not found yet')
        : context.uiCopy(zh: '讓大家找到你', en: 'Let people find you');
    final detail = _checking
        ? context.uiCopy(
            zh: '正在查詢你目前的公開個人檔案。',
            en: 'Looking up your current public profile.',
          )
        : _failed
        ? context.uiCopy(
            zh: '連線失敗不代表尚未公開，請稍後重新確認。',
            en: 'A connection failure does not mean your profile is private. Try again.',
          )
        : indexed
        ? context.uiCopy(
            zh: changed
                ? '網路上仍顯示先前版本。發布變更後，請重新確認。'
                : '別人可以用公開名稱或帳號搜尋你。推薦清單會排除自己及已追蹤的人。',
            en: changed
                ? 'The previous version is still online. Publish your changes, then check again.'
                : 'People can search your public name or handle. Recommendations exclude yourself and accounts already followed.',
          )
        : context.uiCopy(
            zh: hasLocal
                ? '這次查詢尚未找到你的公開檔案。若已同步，請稍後重新確認。'
                : '想讓別人也找到你嗎？選擇公開暱稱與帳號，就能讓人搜尋與追蹤你。你也可以先繼續探索。',
            en: hasLocal
                ? 'Publish so people can find and follow you. If you already synced, check again shortly.'
                : 'Choose a public name and handle so people can find and follow you. You can explore without publishing a profile.',
          );
    return Card(
      key: const Key('public_profile_status_card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(detail, style: const TextStyle(fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (widget.allowEdit)
                  TextButton.icon(
                    key: const Key('public_profile_edit'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              EditProfileScreen(db: widget.db, did: widget.did),
                        ),
                      );
                      if (mounted) await _check();
                    },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(
                      context.uiCopy(
                        zh: indexed || _failed ? '管理公開檔案' : '預覽並設定公開檔案',
                        en: indexed || _failed
                            ? 'Manage public profile'
                            : 'Preview and set up profile',
                      ),
                    ),
                  ),
                if (widget.onDismiss != null)
                  TextButton(
                    key: const Key('public_profile_later'),
                    onPressed: widget.onDismiss,
                    child: Text(context.uiCopy(zh: '稍後', en: 'Not now')),
                  ),
                TextButton(
                  key: const Key('public_profile_check'),
                  onPressed: _checking ? null : _check,
                  child: Text(context.uiCopy(zh: '重新確認', en: 'Check again')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
