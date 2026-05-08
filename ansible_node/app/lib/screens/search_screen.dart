import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'murmur_detail_screen.dart';

enum _SearchScope { all, private, circle, public }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.contentItems = const []});

  final List<ContentItem> contentItems;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController(text: '廢墟');
  _SearchScope _scope = _SearchScope.all;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim();
    final notes = _matches(ContentMode.note, query);
    final murmurs = _matches(ContentMode.murmur, query);
    final total = notes.length + murmurs.length + _sampleThreads.length;

    return AnsibleScreenScaffold(
      title: 'SEARCH',
      leadingLabel: '← 草地',
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: TextField(
              controller: _queryController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除',
                        onPressed: () {
                          _queryController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                hintText: '搜尋 murmur、筆記、討論',
                filled: true,
                fillColor: AnsibleDesign.paperDeep.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AnsibleDesign.ink),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ScopeChip(
                  label: '全部',
                  selected: _scope == _SearchScope.all,
                  onTap: () => setState(() => _scope = _SearchScope.all),
                ),
                _ScopeChip(
                  label: '我的',
                  selected: _scope == _SearchScope.private,
                  onTap: () => setState(() => _scope = _SearchScope.private),
                ),
                _ScopeChip(
                  label: '圈內',
                  selected: _scope == _SearchScope.circle,
                  onTap: () => setState(() => _scope = _SearchScope.circle),
                ),
                _ScopeChip(
                  label: '公開',
                  selected: _scope == _SearchScope.public,
                  onTap: () => setState(() => _scope = _SearchScope.public),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Row(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '找到 '),
                      TextSpan(
                        text: '$total',
                        style: const TextStyle(
                          color: AnsibleDesign.ink,
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                      const TextSpan(text: ' 處提及'),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const Spacer(),
                const Text(
                  '↓ 相關',
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9.5,
                    letterSpacing: 1.1,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          _ResultSection(
            label: '筆記 · NOTES · ${notes.length}',
            rows: [
              if (notes.isEmpty)
                for (final row in _sampleNotes)
                  _ResultRow(data: row, query: query)
              else
                for (final item in notes)
                  _ResultRow(
                    data: _ResultData.fromContentItem(item),
                    query: query,
                  ),
            ],
          ),
          _ResultSection(
            label: '碎念 · MURMURS · ${murmurs.length}',
            rows: [
              if (murmurs.isEmpty)
                for (final row in _sampleMurmurs)
                  _ResultRow(data: row, query: query)
              else
                for (final item in murmurs)
                  _ResultRow(
                    data: _ResultData.fromContentItem(item),
                    query: query,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MurmurDetailScreen(murmur: item),
                        ),
                      );
                    },
                  ),
            ],
          ),
          _ResultSection(
            label: '討論串 · FORUM · ${_sampleThreads.length}',
            rows: [
              for (final row in _sampleThreads)
                _ResultRow(data: row, query: query),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<ContentItem> _matches(ContentMode mode, String query) {
    final items = widget.contentItems.where((item) {
      if (item.mode != mode) return false;
      if (_scope == _SearchScope.private &&
          item.visibility != ContentVisibility.private) {
        return false;
      }
      if (_scope == _SearchScope.public &&
          item.visibility != ContentVisibility.public) {
        return false;
      }
      if (_scope == _SearchScope.circle &&
          item.visibility == ContentVisibility.private) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${item.title ?? ''}\n${item.body}'.toLowerCase().contains(
        query.toLowerCase(),
      );
    }).toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(12).toList();
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AnsibleDesign.ink : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AnsibleDesign.paper : AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          label,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        ),
        AnsibleRuleGroup(children: rows),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.data, required this.query, this.onTap});

  final _ResultData data;
  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  data.kindLabel,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    letterSpacing: 1.4,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: data.visibilityColor,
                  ),
                ),
                if (data.title.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AnsibleDesign.ink,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                Text(
                  data.when,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              _highlight(data.body, query),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _highlight(String text, String query) {
    if (query.isEmpty) return TextSpan(text: text);
    final source = text.toLowerCase();
    final needle = query.toLowerCase();
    final index = source.indexOf(needle);
    if (index < 0) return TextSpan(text: text);
    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, index)),
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            color: AnsibleDesign.ink,
            backgroundColor: AnsibleDesign.accentSoft,
          ),
        ),
        TextSpan(text: text.substring(index + query.length)),
      ],
    );
  }
}

class _ResultData {
  const _ResultData({
    required this.kindLabel,
    required this.title,
    required this.body,
    required this.when,
    required this.visibilityColor,
  });

  factory _ResultData.fromContentItem(ContentItem item) {
    final kind = switch (item.mode) {
      ContentMode.murmur => 'MURM',
      ContentMode.note => 'NOTE',
      ContentMode.post => 'POST',
      ContentMode.discussion => 'THRD',
    };
    return _ResultData(
      kindLabel: kind,
      title: item.title ?? '',
      body: item.body,
      when: _formatAge(item.updatedAt),
      visibilityColor: _visibilityColor(item.visibility),
    );
  }

  final String kindLabel;
  final String title;
  final String body;
  final String when;
  final Color visibilityColor;
}

const _sampleNotes = [
  _ResultData(
    kindLabel: 'NOTE',
    title: '廢墟中的協作',
    body: '信任不是 default-on 的，這是廢墟狀態下協作的前提。',
    when: '今日',
    visibilityColor: AnsibleDesign.inkMuted,
  ),
  _ResultData(
    kindLabel: 'NOTE',
    title: '關於 Le Guin 的 Ansible',
    body: '廢墟的另一面是 distance；ansible 跨越的不只是空間。',
    when: '3天',
    visibilityColor: AnsibleDesign.inkMuted,
  ),
];

const _sampleMurmurs = [
  _ResultData(
    kindLabel: 'MURM',
    title: '',
    body: 'Anna Tsing 寫的 patches 並不浪漫，是在廢墟之後才看見的某種共生。',
    when: '2小時',
    visibilityColor: AnsibleDesign.inkMuted,
  ),
  _ResultData(
    kindLabel: 'MURM',
    title: '',
    body: '為什麼自己會抗拒「重建」這個詞，也許因為廢墟本身已經是一種完整。',
    when: '昨日',
    visibilityColor: AnsibleDesign.accent,
  ),
];

const _sampleThreads = [
  _ResultData(
    kindLabel: 'THRD',
    title: '我們在「廢墟」裡到底在尋找什麼？',
    body: '林下 · 23 回 · 公開',
    when: '2小時',
    visibilityColor: AnsibleDesign.spore,
  ),
  _ResultData(
    kindLabel: 'THRD',
    title: '荒涼感作為一種介面語言',
    body: 'Tris · 14 回 · 公開',
    when: '3天',
    visibilityColor: AnsibleDesign.spore,
  ),
];

Color _visibilityColor(ContentVisibility visibility) {
  return switch (visibility) {
    ContentVisibility.private => AnsibleDesign.inkMuted,
    ContentVisibility.unlisted => AnsibleDesign.accent,
    ContentVisibility.public => AnsibleDesign.spore,
  };
}

String _formatAge(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inHours < 1) return '${diff.inMinutes.clamp(0, 59)}分';
  if (diff.inDays < 1) return '${diff.inHours}小時';
  return '${diff.inDays}天';
}
