import 'dart:async';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/app_view_timeline_client.dart';
import '../services/ops_dispatch_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/author_label.dart';

/// Detail view for a standalone content item (murmur/note): the full content as
/// the head, plus a comment thread. Comments are `post` ops keyed by the
/// content's entity id (`threadId == contentId`); they read back from the
/// AppView's `GET /api/v1/thread/:thread_id`. The board-less content has no
/// local board sync, so the AppView is the only comment read path.
class ContentDetailScreen extends StatefulWidget {
  const ContentDetailScreen({
    super.key,
    required this.db,
    required this.localDid,
    required this.contentId,
    required this.authorDid,
    required this.body,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.title,
    this.timeAgo,
    this.appViewBaseUrl,
  });

  final AppDatabase db;
  final String localDid;
  final String contentId;
  final String authorDid;
  final String body;
  final String? title;
  final String? timeAgo;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;

  /// Defaults to the build's configured AppView; injectable for tests.
  final String? appViewBaseUrl;

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  final _composer = TextEditingController();
  List<_Comment> _comments = const [];
  bool _loading = true;
  bool _posting = false;

  String get _appViewBaseUrl =>
      widget.appViewBaseUrl ?? AppEnvironment.appViewBaseUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_appViewBaseUrl.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final page = await AppViewTimelineClient(
        baseUrl: _appViewBaseUrl,
      ).fetchThread(threadId: widget.contentId);
      if (!mounted) return;
      setState(() {
        _comments = _toComments(page.items);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<_Comment> _toComments(List<AppViewTimelineItem> items) {
    final comments = items
        .where((i) => i.entityType == 'comment')
        .map(
          (i) => _Comment(
            authorDid: i.authorDid,
            body: (i.payload['content'] ?? i.payload['body'] ?? '').toString(),
            createdAt: i.createdAt,
          ),
        )
        .toList();
    // Oldest-first reads naturally as a conversation.
    comments.sort((a, b) {
      final at = a.createdAt, bt = b.createdAt;
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });
    return comments;
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final entry = CrdtOpBuilder.createComment(
        authorDid: widget.localDid,
        entityId: const Uuid().v4(),
        targetId: widget.contentId,
        content: text,
      );
      await widget.opsDispatchService.signAndEnqueue(entry);
      unawaited(widget.onFlushPendingOps());
      if (!mounted) return;
      setState(() {
        // Optimistic: the AppView needs a beat to ingest before fetchThread
        // returns it, so show the comment immediately.
        _comments = [
          ..._comments,
          _Comment(
            authorDid: widget.localDid,
            body: text,
            createdAt: DateTime.now().toUtc(),
          ),
        ];
        _composer.clear();
        _posting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '貼文', en: 'POST'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _head(context),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    child: Text(
                      context.uiCopy(
                        zh: '還沒有留言，搶頭香！',
                        en: 'No comments yet — be the first.',
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  )
                else
                  for (final c in _comments) _commentRow(context, c),
              ],
            ),
          ),
          _composerBar(context),
        ],
      ),
    );
  }

  Widget _head(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.rule, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: AuthorLabel(
                  did: widget.authorDid,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AnsibleDesign.ink,
                  ),
                ),
              ),
              if (widget.timeAgo != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· ${widget.timeAgo}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ],
          ),
          if ((widget.title ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.title!,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AnsibleDesign.ink,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            widget.body.isEmpty ? context.l10n.noContentYet : widget.body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AnsibleDesign.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentRow(BuildContext context, _Comment c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthorLabel(
            did: c.authorDid,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            c.body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AnsibleDesign.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(top: BorderSide(color: AnsibleDesign.rule, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
                decoration: InputDecoration(
                  hintText: context.uiCopy(zh: '寫留言…', en: 'Write a comment…'),
                  isDense: true,
                  filled: true,
                  fillColor: AnsibleDesign.paperDeep.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _posting ? null : _send,
              icon: const Icon(Icons.send, size: 20, color: AnsibleDesign.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _Comment {
  const _Comment({
    required this.authorDid,
    required this.body,
    this.createdAt,
  });

  final String authorDid;
  final String body;
  final DateTime? createdAt;
}
