import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../theme/ansible_design.dart';
import '../widgets/content_visibility_sheet.dart';
import 'note_detail_screen.dart';

class NoteWorkspaceScreen extends StatelessWidget {
  const NoteWorkspaceScreen({
    super.key,
    this.authorDid,
    this.notes = const [],
    this.murmurs = const [],
    this.contentItemRepository,
    this.onContentItemsChanged,
  });

  final String? authorDid;
  final List<ContentItem> notes;
  final List<ContentItem> murmurs;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            const Expanded(
              child: AnsibleSectionHead(
                zh: '草地',
                en: 'WORKING NOTES',
                action: '↓ 最近',
              ),
            ),
            OutlinedButton.icon(
              onPressed: contentItemRepository == null || authorDid == null
                  ? null
                  : () => _openCreateNoteEditor(context),
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('新增筆記'),
            ),
          ],
        ),
        if (notes.isEmpty)
          const _EmptyNotesPreview()
        else
          for (final note in notes)
            _NoteRow(
              note: note,
              contentItemRepository: contentItemRepository,
              onContentItemsChanged: onContentItemsChanged,
            ),
        const SizedBox(height: 18),
        const AnsibleSectionHead(zh: '散落', en: 'LOOSE MURMURS', action: '↗ 編入'),
        if (murmurs.isEmpty)
          const Text(
            '還沒有散落的碎念。',
            style: TextStyle(
              fontSize: 13,
              color: AnsibleDesign.inkMuted,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final murmur in murmurs.reversed.take(5))
            _MurmurRow(murmur: murmur),
        const SizedBox(height: 20),
        const AnsibleSectionHead(zh: '來源 · LINEAGE', en: 'LOCAL CONTENT GRAPH'),
        const _LineagePreview(),
      ],
    );
  }

  Future<void> _openCreateNoteEditor(BuildContext context) async {
    final repository = contentItemRepository;
    final did = authorDid;
    if (repository == null || did == null) return;

    final result = await Navigator.of(context).push<_CreateNoteResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateNoteEditorScreen(murmurs: murmurs),
      ),
    );
    if (result == null) return;

    final now = DateTime.now().toUtc();
    await repository.create(
      ContentItem(
        id: const Uuid().v4(),
        authorDid: did,
        mode: ContentMode.note,
        title: result.title,
        body: result.body,
        status: ContentStatus.active,
        visibility: ContentVisibility.private,
        createdAt: now,
        updatedAt: now,
        localOnly: true,
      ),
    );
    await onContentItemsChanged?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已建立筆記')));
  }
}

class _CreateNoteResult {
  const _CreateNoteResult({required this.title, required this.body});

  final String title;
  final String body;
}

class _CreateNoteEditorScreen extends StatefulWidget {
  const _CreateNoteEditorScreen({required this.murmurs});

  @override
  State<_CreateNoteEditorScreen> createState() =>
      _CreateNoteEditorScreenState();

  final List<ContentItem> murmurs;
}

class _CreateNoteEditorScreenState extends State<_CreateNoteEditorScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _drawerOpen = true;
  bool _showErrors = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleMissing = _showErrors && _titleController.text.trim().isEmpty;
    final bodyMissing = _showErrors && _bodyController.text.trim().isEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('取消'),
                    style: TextButton.styleFrom(
                      foregroundColor: AnsibleDesign.inkMuted,
                      textStyle: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _EditorDot(color: AnsibleDesign.spore, size: 5),
                      SizedBox(width: 8),
                      Text(
                        '草稿保留 · 本機',
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9.5,
                          color: AnsibleDesign.inkFaint,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AnsibleDesign.paperElev,
                      foregroundColor: AnsibleDesign.ink,
                      side: const BorderSide(
                        color: AnsibleDesign.rule,
                        width: 0.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                    ),
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '編輯中 · EDITING',
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9.5,
                    color: AnsibleDesign.inkFaint,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('note_title_field'),
                      controller: _titleController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.2,
                        color: AnsibleDesign.ink,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: '末日松茸採集',
                        hintStyle: TextStyle(
                          color: AnsibleDesign.inkFaint,
                          fontSize: 28,
                          fontStyle: FontStyle.normal,
                          fontWeight: FontWeight.w500,
                        ),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.ruleSoft,
                            width: 0.5,
                          ),
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.ruleSoft,
                            width: 0.5,
                          ),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.accent,
                            width: 1,
                          ),
                        ),
                        contentPadding: EdgeInsets.fromLTRB(0, 4, 0, 8),
                      ),
                    ),
                    if (titleMissing) const _InlineError('請輸入標題'),
                    const SizedBox(height: 10),
                    const _EditorVisibilityRow(),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('note_body_field'),
                      controller: _bodyController,
                      minLines: 9,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.8,
                        color: AnsibleDesign.ink,
                      ),
                      decoration: const InputDecoration(
                        filled: false,
                        hintText: '繼續寫下去，或從下方拖一個 murmur 進來……',
                        hintStyle: TextStyle(
                          color: AnsibleDesign.inkFaint,
                          fontSize: 15.5,
                          height: 1.8,
                          fontStyle: FontStyle.italic,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (bodyMissing) const _InlineError('請輸入內文'),
                  ],
                ),
              ),
            ),
            const _EditorFormatToolbar(),
            _EditorMurmurDrawer(
              open: _drawerOpen,
              murmurs: widget.murmurs,
              onToggle: () => setState(() => _drawerOpen = !_drawerOpen),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    setState(() => _showErrors = true);
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) return;
    Navigator.of(context).pop(_CreateNoteResult(title: title, body: body));
  }
}

class _EditorVisibilityRow extends StatelessWidget {
  const _EditorVisibilityRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        AnsibleStatusChip(label: 'private', dot: AnsibleDesign.inkMuted),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '還沒讓任何人看見',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AnsibleDesign.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorFormatToolbar extends StatelessWidget {
  const _EditorFormatToolbar();

  @override
  Widget build(BuildContext context) {
    const tools = ['B', 'I', 'U', '""', '§', '↗'];
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AnsibleDesign.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AnsibleDesign.ink.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < tools.length; i++) ...[
            Expanded(
              child: Center(
                child: Text(
                  tools[i],
                  style: TextStyle(
                    color: AnsibleDesign.paper,
                    fontSize: 14,
                    fontWeight: tools[i] == 'B'
                        ? FontWeight.w700
                        : FontWeight.w400,
                    fontStyle: tools[i] == 'I'
                        ? FontStyle.italic
                        : FontStyle.normal,
                    decoration: tools[i] == 'U'
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: AnsibleDesign.paper,
                  ),
                ),
              ),
            ),
            if (i < tools.length - 1)
              Container(
                width: 0.5,
                height: 18,
                color: AnsibleDesign.paper.withValues(alpha: 0.16),
              ),
          ],
        ],
      ),
    );
  }
}

class _EditorMurmurDrawer extends StatelessWidget {
  const _EditorMurmurDrawer({
    required this.open,
    required this.murmurs,
    required this.onToggle,
  });

  final bool open;
  final List<ContentItem> murmurs;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final items = murmurs.reversed.take(6).toList();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          top: BorderSide(color: AnsibleDesign.rule, width: 0.5),
          left: BorderSide(color: AnsibleDesign.rule, width: 0.5),
          right: BorderSide(color: AnsibleDesign.rule, width: 0.5),
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AnsibleDesign.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '編入 · DRAW IN',
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9.5,
                      color: AnsibleDesign.inkFaint,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: AnsibleDesign.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            SizedBox(
              height: 112,
              child: items.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          '還沒有可以編入的 murmur。',
                          style: TextStyle(
                            color: AnsibleDesign.inkMuted,
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      itemBuilder: (context, index) =>
                          _EditorMurmurCard(murmur: items[index]),
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemCount: items.length,
                    ),
            ),
        ],
      ),
    );
  }
}

class _EditorMurmurCard extends StatelessWidget {
  const _EditorMurmurCard({required this.murmur});

  final ContentItem murmur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MURMUR · ${_formatDate(murmur.createdAt)}',
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 8.5,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            murmur.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AnsibleDesign.ink,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        message,
        style: const TextStyle(color: AnsibleDesign.danger, fontSize: 12),
      ),
    );
  }
}

class _EditorDot extends StatelessWidget {
  const _EditorDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _EmptyNotesPreview extends StatelessWidget {
  const _EmptyNotesPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '還沒有筆記',
            style: TextStyle(
              fontSize: 18,
              color: AnsibleDesign.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '碎念會先散落在本地；等它們慢慢靠近，再編成一篇筆記。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AnsibleDesign.inkMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    this.contentItemRepository,
    this.onContentItemsChanged,
  });

  final ContentItem note;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    note.title ?? 'Untitled note',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                ),
                Text(
                  _formatDate(note.updatedAt),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    color: AnsibleDesign.inkFaint,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              note.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            _VisibilityMenu(
              note: note,
              contentItemRepository: contentItemRepository,
              onContentItemsChanged: onContentItemsChanged,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }
}

class _VisibilityMenu extends StatelessWidget {
  const _VisibilityMenu({
    required this.note,
    this.contentItemRepository,
    this.onContentItemsChanged,
  });

  final ContentItem note;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;

  @override
  Widget build(BuildContext context) {
    final meta = contentVisibilityMeta(note.visibility);
    final chip = AnsibleStatusChip(
      key: Key('visibility_chip_${note.id}'),
      label: meta.label,
      dot: meta.dot,
    );
    if (contentItemRepository == null) return chip;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showVisibilitySheet(context),
      child: chip,
    );
  }

  Future<void> _showVisibilitySheet(BuildContext context) async {
    final visibility = await showContentVisibilitySheet(
      context: context,
      current: note.visibility,
      subjectLabel: '這篇 note',
    );
    if (visibility == null) return;
    if (!context.mounted) return;
    await _updateVisibility(context, visibility);
  }

  Future<void> _updateVisibility(
    BuildContext context,
    ContentVisibility visibility,
  ) async {
    if (visibility == note.visibility || contentItemRepository == null) return;
    final now = DateTime.now().toUtc();

    await contentItemRepository!.update(
      ContentItem(
        id: note.id,
        authorDid: note.authorDid,
        mode: note.mode,
        body: note.body,
        status: note.status,
        visibility: visibility,
        createdAt: note.createdAt,
        updatedAt: now,
        subjectId: note.subjectId,
        title: note.title,
        publishedAt: visibility == ContentVisibility.public
            ? note.publishedAt ?? now
            : note.publishedAt,
        isDeleted: note.isDeleted,
        localOnly: visibility == ContentVisibility.private,
      ),
    );
    await onContentItemsChanged?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('可見性已更新')));
  }
}

class _MurmurRow extends StatelessWidget {
  const _MurmurRow({required this.murmur});

  final ContentItem murmur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              murmur.body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AnsibleDesign.ink,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatTime(murmur.createdAt),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

class _LineagePreview extends StatelessWidget {
  const _LineagePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '由 murmur 編成的筆記會在這裡保留來源。',
            style: TextStyle(
              color: AnsibleDesign.inkMuted,
              height: 1.55,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'MURMUR · NOTE · THREAD',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
