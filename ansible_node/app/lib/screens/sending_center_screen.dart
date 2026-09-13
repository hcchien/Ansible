import 'dart:convert';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/app_l10n.dart';
import '../services/delivery_diagnostics.dart';

class SendingCenterScreen extends StatefulWidget {
  const SendingCenterScreen({
    super.key,
    required this.did,
    required this.repository,
    required this.db,
    required this.onRetry,
    required this.onSync,
  });
  final String did;
  final AppDatabase db;
  final DriftOpsQueueRepository repository;
  final Future<void> Function(OpsQueueEntry) onRetry;
  final Future<void> Function() onSync;
  @override
  State<SendingCenterScreen> createState() => _SendingCenterScreenState();
}

class _SendingCenterScreenState extends State<SendingCenterScreen> {
  List<OpsQueueEntry> _entries = [];
  List<ContentItem> _localItems = [];
  List<Map<String, dynamic>> _diagnostics = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.repository.listDelivery(widget.did);
      final local = await DriftContentItemRepository(
        widget.db,
      ).list(authorDid: widget.did);
      final diagnostics = await DeliveryDiagnostics.shared.read(widget.did);
      if (mounted) {
        setState(() {
          _entries = entries;
          _diagnostics = diagnostics;
          _localItems = local
              .where(
                (item) => !entries.any(
                  (entry) =>
                      entry.entityId == item.id &&
                      !entry.createdAt.isBefore(item.updatedAt),
                ),
              )
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.uiCopy(
            zh: '無法讀取傳送紀錄，請重試。',
            en: 'Could not read delivery history. Please retry.',
          ),
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.uiCopy(
            zh: '操作未完成，資料仍保留。請檢查連線或重新授權。',
            en: 'Action incomplete; data is retained. Check your connection or authorize again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _preview(OpsQueueEntry entry) {
    try {
      final payload = jsonDecode(utf8.decode(base64Decode(entry.payload)));
      if (payload is Map &&
          payload['encrypted'] != true &&
          !payload.containsKey('ciphertext')) {
        return (payload['title'] ??
                payload['body'] ??
                payload['content'] ??
                entry.entityType)
            .toString();
      }
    } catch (_) {}
    return entry.entityType;
  }

  String _state(OpsQueueEntry e) => switch (e.status) {
    'synced' => context.uiCopy(zh: 'Relay 已接受', en: 'Accepted by Relay'),
    'awaiting_authorization' => context.uiCopy(
      zh: '已存本機，等待簽署授權',
      en: 'Saved locally; awaiting signing authorization',
    ),
    'blocked' => context.uiCopy(
      zh: '傳送受阻，可重試',
      en: 'Delivery blocked; retry available',
    ),
    'rejected' => context.uiCopy(
      zh: 'Relay 已拒絕，請檢查內容或權限',
      en: 'Rejected by Relay; check content or permissions',
    ),
    'sent' => context.uiCopy(
      zh: '等待 Relay 確認',
      en: 'Awaiting Relay confirmation',
    ),
    'cancelled' => context.uiCopy(zh: '已停止這次傳送', en: 'Delivery cancelled'),
    _ => context.uiCopy(zh: '等待傳送', en: 'Queued for delivery'),
  };
  Future<void> _cancel(OpsQueueEntry entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.uiCopy(
            zh: '停止尚未嘗試的傳送？',
            en: 'Cancel this unattempted delivery?',
          ),
        ),
        content: Text(
          context.uiCopy(
            zh: '只停止這個操作，本機內容仍保留。這不會刪除已傳到其他地方的副本。',
            en: 'This stops this operation and retains local content. It does not delete copies already delivered elsewhere.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.uiCopy(zh: '返回', en: 'Back')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.uiCopy(zh: '停止傳送', en: 'Cancel delivery')),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await widget.repository.cancelUnattempted(entry.opId, widget.did);
  }

  Future<void> _copyDiagnostics() async {
    final info = await PackageInfo.fromPlatform();
    final report = {
      'app': 'Elix',
      'version': info.version,
      'build': info.buildNumber,
      'events': _diagnostics,
    };
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(report)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '已複製不含貼文內容、金鑰或憑證的診斷紀錄。',
              en: 'Copied diagnostics without post content, keys or credentials.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.uiCopy(zh: '傳送中心', en: 'Sending center')),
      actions: [
        IconButton(
          onPressed: _busy ? null : () => _run(_load),
          icon: const Icon(Icons.refresh),
          tooltip: context.uiCopy(zh: '重新整理', en: 'Refresh'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.uiCopy(
            zh: '這裡顯示本機操作的傳送狀態。Relay 接受後即完成同步；網頁索引是另一個步驟。尚未加入佇列的公開內容，請按同步授權傳送。外部 Nostr／Fediverse 的各目標進度仍在同步設定中查看。',
            en: 'These are local operation delivery states. Relay acceptance completes sync; Web indexing is separate. Use Sync to authorize public content not yet queued. Per-target Nostr/Fediverse progress remains in sync settings.',
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onSync),
              child: Text(
                context.uiCopy(zh: '同步與授權', en: 'Sync and authorize'),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _copyDiagnostics,
              child: Text(context.uiCopy(zh: '複製診斷紀錄', en: 'Copy diagnostics')),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_entries.isEmpty)
          Text(
            context.uiCopy(
              zh: '尚無傳送操作。私人內容只會留在本機。',
              en: 'No delivery operations yet. Private content remains local.',
            ),
          ),
        for (final item in _localItems)
          Card(
            child: ListTile(
              title: Text(
                (item.title?.isNotEmpty ?? false) ? item.title! : item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.visibility == ContentVisibility.private
                    ? context.uiCopy(
                        zh: '已存本機 · 私人內容',
                        en: 'Saved on this device · Private',
                      )
                    : context.uiCopy(
                        zh: '已存本機 · 尚未加入 Relay 傳送佇列',
                        en: 'Saved locally · Not yet queued for Relay',
                      ),
              ),
              trailing: item.visibility == ContentVisibility.public
                  ? TextButton(
                      onPressed: _busy ? null : () => _run(widget.onSync),
                      child: Text(context.uiCopy(zh: '同步', en: 'Sync')),
                    )
                  : null,
            ),
          ),
        for (final entry in _entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _state(entry),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _preview(entry),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SelectableText('${entry.entityType} · ${entry.opId}'),
                  Text(
                    context.uiCopy(
                      zh: '建立：${entry.createdAt.toLocal()}',
                      en: 'Created: ${entry.createdAt.toLocal()}',
                    ),
                  ),
                  if (entry.sentAt != null)
                    Text(
                      context.uiCopy(
                        zh: '最近嘗試：${entry.sentAt!.toLocal()}',
                        en: 'Last attempt: ${entry.sentAt!.toLocal()}',
                      ),
                    ),
                  if (_diagnostics
                          .where(
                            (d) =>
                                d['op_id'] == entry.opId && d['reason'] != null,
                          )
                          .lastOrNull
                      case final reason?)
                    Text('${reason['at']} · ${reason['reason']}'),
                  Wrap(
                    children: [
                      if (![
                        'synced',
                        'cancelled',
                        'rejected',
                      ].contains(entry.status))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => widget.onRetry(entry)),
                          child: Text(
                            context.uiCopy(zh: '重試這一項', en: 'Retry this item'),
                          ),
                        ),
                      if (entry.sentAt == null &&
                          [
                            'pending',
                            'awaiting_authorization',
                            'blocked',
                          ].contains(entry.status))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => _cancel(entry)),
                          child: Text(
                            context.uiCopy(zh: '停止傳送', en: 'Cancel delivery'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
