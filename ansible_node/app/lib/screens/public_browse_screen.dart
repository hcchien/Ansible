import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';
import '../services/discovery_client.dart';
import '../widgets/author_label.dart';
import 'public_content_screen.dart';

/// Anonymous public browse/search. Creating an identity is an explicit action.
class PublicBrowseScreen extends StatefulWidget {
  const PublicBrowseScreen({super.key, this.client, this.onRegister});
  final DiscoveryClient? client;
  final void Function(DiscoveredPost)? onRegister;
  @override
  State<PublicBrowseScreen> createState() => _PublicBrowseScreenState();
}

class _PublicBrowseScreenState extends State<PublicBrowseScreen> {
  late final DiscoveryClient _client =
      widget.client ?? DiscoveryClient(appViewBaseUrl: '');
  final _query = TextEditingController();
  List<DiscoveredPost> _posts = [];
  bool _loading = false;
  bool _failed = false;
  bool _partial = false;
  int _request = 0;
  int? _cursor;
  bool _more = false;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final q = _query.text.trim();
      final result = q.isEmpty ? null : await _client.search(query: q);
      final page = q.isEmpty
          ? await _client.explorePage(cursor: more ? _cursor : null)
          : null;
      final posts = result?.posts ?? page!.items;
      if (mounted && request == _request) {
        setState(() {
          _posts = [...(more ? _posts : <DiscoveredPost>[]), ...posts];
          _partial = result?.partialFailure ?? false;
          _cursor = page?.cursor;
          _more = page?.hasMore ?? false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.uiCopy(zh: '探索公開內容', en: 'Explore public content')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.uiCopy(
            zh: '正在瀏覽公開內容。發表或追蹤時，再建立你的身分。',
            en: 'Browse public content. Create your identity when you want to post or follow.',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: context.uiCopy(
              zh: '搜尋公開內容',
              en: 'Search public content',
            ),
            helperText: context.uiCopy(
              zh: '按搜尋才會將查詢送至 Relay',
              en: 'Your query is sent to the Relay only when you search',
            ),
            suffixIcon: IconButton(
              onPressed: _search,
              icon: const Icon(Icons.search),
              tooltip: context.uiCopy(zh: '搜尋', en: 'Search'),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_partial)
          Text(
            context.uiCopy(
              zh: '部分公開搜尋服務暫時無法使用，結果可能不完整。',
              en: 'Some public search services are unavailable; results may be incomplete.',
            ),
          ),
        if (_failed) ...[
          Text(
            context.uiCopy(
              zh: '公開內容載入失敗，請重試。',
              en: 'Public content could not be loaded. Please retry.',
            ),
          ),
          TextButton(
            onPressed: _search,
            child: Text(context.uiCopy(zh: '重試', en: 'Retry')),
          ),
        ],
        if (!_loading && !_failed && !_more && _posts.isEmpty)
          Text(
            context.uiCopy(zh: '沒有符合的公開貼文。', en: 'No matching public posts.'),
          ),
        if (_more)
          TextButton(
            onPressed: _loading ? null : () => _search(more: true),
            child: Text(
              context.uiCopy(zh: '載入更多公開貼文', en: 'Load more public posts'),
            ),
          ),
        for (final post in _posts)
          Card(
            child: ListTile(
              title: AuthorLabel(did: post.authorDid),
              subtitle: Text(
                post.body.isEmpty
                    ? (post.payload['title'] ?? '').toString()
                    : post.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PublicContentScreen(
                    post: post,
                    client: _client,
                    onInteract: widget.onRegister == null
                        ? null
                        : () => widget.onRegister!(post),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
