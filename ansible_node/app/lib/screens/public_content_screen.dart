import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../services/composer_draft_store.dart';
import 'post_composer_screen.dart';
import 'sync_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ansible_domain/ansible_domain.dart';
import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/discovery_client.dart';
import '../widgets/author_label.dart';
import '../widgets/content_trust_badge.dart';

/// Exact public content reader. Subscription is not a prerequisite to read;
/// the Relay still enforces visibility and board access at every request.
class PublicContentScreen extends StatefulWidget {
  const PublicContentScreen({
    super.key,
    required this.post,
    required this.client,
    this.onInteract,
    this.db,
    this.localDid,
  });
  final DiscoveredPost post;
  final DiscoveryClient client;
  final VoidCallback? onInteract;
  final AppDatabase? db;
  final String? localDid;
  @override
  State<PublicContentScreen> createState() => _PublicContentScreenState();
}

class _PublicContentScreenState extends State<PublicContentScreen> {
  DiscoveredPost? _post;
  List<AppViewTimelineItem> _replies = [];
  bool _loading = true;
  String? _error;
  bool _more = false;
  int? _cursor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = more
          ? _post!
          : await widget.client.content(
              widget.post.entityType,
              widget.post.entityId,
            );
      if (!mounted) return;
      setState(() {
        _post = post;
        if (!more) _replies = [];
      });
      final page = await widget.client.thread(
        id: post.threadId ?? post.entityId,
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        _post = post;
        final items = page.items.where(
          (p) =>
              p.entityId != post.entityId &&
              ['post', 'comment'].contains(p.entityType),
        );
        _replies =
            {
              for (final item in [
                ...(more ? _replies : <AppViewTimelineItem>[]),
                ...items,
              ])
                item.entityId: item,
            }.values.toList()..sort(
              (a, b) => (a.createdAt ?? DateTime(1970)).compareTo(
                b.createdAt ?? DateTime(1970),
              ),
            );
        _cursor = page.nextCursor;
        _more = page.hasMore;
      });
    } on PublicContentException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.status == 410
              ? context.uiCopy(zh: '這篇內容已刪除。', en: 'This content was deleted.')
              : context.uiCopy(
                  zh: '找不到可公開閱讀的內容。內容可能已移除或需要存取權限。',
                  en: 'Public content is unavailable. It may have been removed or require access.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.uiCopy(
            zh: '目前無法連線，請重試。',
            en: 'Cannot connect right now. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reply() async {
    final db = widget.db;
    final did = widget.localDid;
    final post = _post;
    if (db == null || did == null || post == null) return;
    final result = await Navigator.of(context).push<PostComposerResult>(
      MaterialPageRoute(
        builder: (_) => PostComposerScreen(
          authorDid: did,
          draftTarget: 'thread:${post.threadId ?? post.entityId}',
        ),
      ),
    );
    if (result == null) return;
    final entityId = const Uuid().v4();
    final op =
        (post.boardId != null &&
                    (post.threadId != null || post.entityType == 'thread')
                ? CrdtOpBuilder.createPost(
                    authorDid: did,
                    entityId: entityId,
                    boardId: post.boardId!,
                    threadId: post.threadId ?? post.entityId,
                    content: result.content,
                    mentions: result.mentions,
                    mentionDids: result.mentionDids,
                  )
                : CrdtOpBuilder.createComment(
                    authorDid: did,
                    entityId: entityId,
                    targetId: post.entityId,
                    content: result.content,
                    mentions: result.mentions,
                    mentionDids: result.mentionDids,
                  ))
            .copyWith(status: 'awaiting_authorization');
    try {
      await DriftOpsQueueRepository(db).enqueue(op);
      if (result.draftKey != null) {
        await ComposerDraftStore.shared.clear(result.draftKey!);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SyncSettingsScreen(db: db, localDid: did, initialRetryEntry: op),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(
                zh: '尚未完成傳送，草稿或本機佇列仍保留。',
                en: 'Delivery incomplete. Your draft or local queue is retained.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '公開貼文', en: 'Public post')),
        actions: [
          if (p != null)
            IconButton(
              tooltip: context.uiCopy(zh: '複製貼文連結', en: 'Copy post link'),
              icon: const Icon(Icons.link),
              onPressed: () async {
                final base = AppEnvironment.forumWebBaseUrl.replaceAll(
                  RegExp(r'/+$'),
                  '',
                );
                final path =
                    p.boardId != null &&
                        (p.threadId != null || p.entityType == 'thread')
                    ? 'boards/${Uri.encodeComponent(p.boardId!)}/threads/${Uri.encodeComponent(p.threadId ?? p.entityId)}'
                    : 'content/${Uri.encodeComponent(p.entityType)}/${Uri.encodeComponent(p.entityId)}';
                await Clipboard.setData(ClipboardData(text: '$base/#/$path'));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.uiCopy(zh: '已複製連結', en: 'Link copied'),
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _load,
              child: Text(context.uiCopy(zh: '重試', en: 'Retry')),
            ),
          ],
          if (p != null) ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AuthorLabel(did: p.authorDid),
                if (p.signatureVerified == true)
                  ContentTrustBadge(
                    human: false,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            if (p.signatureVerified != true)
              Text(
                p.signatureVerified == false
                    ? context.uiCopy(
                        zh: '此來源未提供已通過驗證的簽章狀態。',
                        en: 'This source did not provide a verified signature status.',
                      )
                    : context.uiCopy(
                        zh: '缺少簽章驗證資訊，無法判定。',
                        en: 'Signature verification information is missing.',
                      ),
              ),
            const SizedBox(height: 12),
            if (p.payload['title'] is String)
              Text(
                p.payload['title'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            SelectableText(p.body),
            if (widget.onInteract != null ||
                (widget.db != null && widget.localDid != null))
              TextButton.icon(
                onPressed: widget.onInteract ?? _reply,
                icon: const Icon(Icons.reply),
                label: Text(
                  context.uiCopy(zh: '參與討論', en: 'Join the discussion'),
                ),
              ),
            const Divider(height: 32),
            Text(context.uiCopy(zh: '留言', en: 'Replies')),
            for (final reply in _replies)
              ListTile(
                title: AuthorLabel(did: reply.authorDid),
                subtitle: SelectableText(
                  (reply.payload['content'] ?? reply.payload['body'] ?? '')
                      .toString(),
                ),
              ),
            if (_more)
              TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: Text(
                  context.uiCopy(zh: '載入更多留言', en: 'Load more replies'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
