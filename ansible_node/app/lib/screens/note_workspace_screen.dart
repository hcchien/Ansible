import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../theme/ansible_design.dart';
import '../widgets/content_visibility_sheet.dart';
import '../widgets/note_markdown_text.dart';
import 'note_detail_screen.dart';

class NoteWorkspaceScreen extends StatefulWidget {
  const NoteWorkspaceScreen({
    super.key,
    this.authorDid,
    this.notes = const [],
    this.murmurs = const [],
    this.contentItemRepository,
    this.onContentItemsChanged,
    this.onPublishContentItem,
  });

  final String? authorDid;
  final List<ContentItem> notes;
  final List<ContentItem> murmurs;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;
  final Future<void> Function(
    ContentItem item,
    DistributionPreference preference,
  )?
  onPublishContentItem;

  @override
  State<NoteWorkspaceScreen> createState() => _NoteWorkspaceScreenState();
}

class _NoteWorkspaceScreenState extends State<NoteWorkspaceScreen> {
  bool _recentFirst = true;

  @override
  Widget build(BuildContext context) {
    final sortedNotes = [...widget.notes]..sort(_compareNotes);
    final sortedMurmurs = [...widget.murmurs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            const Expanded(
              child: AnsibleSectionHead(zh: '草地', en: 'WORKING NOTES'),
            ),
            TextButton.icon(
              key: const Key('note_sort_toggle'),
              onPressed: () => setState(() => _recentFirst = !_recentFirst),
              icon: Icon(
                _recentFirst
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 15,
              ),
              label: Text(_recentFirst ? '最近' : '最舊'),
              style: TextButton.styleFrom(
                foregroundColor: AnsibleDesign.inkMuted,
                textStyle: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  widget.contentItemRepository == null ||
                      widget.authorDid == null
                  ? null
                  : () => _openCreateNoteEditor(context),
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('新增筆記'),
            ),
          ],
        ),
        if (sortedNotes.isEmpty)
          const _EmptyNotesPreview()
        else
          for (final note in sortedNotes)
            _NoteRow(
              note: note,
              murmurs: sortedMurmurs,
              contentItemRepository: widget.contentItemRepository,
              onContentItemsChanged: widget.onContentItemsChanged,
              onPublishContentItem: widget.onPublishContentItem,
            ),
        const SizedBox(height: 18),
        const AnsibleSectionHead(zh: '散落', en: 'LOOSE MURMURS', action: '↗ 編入'),
        if (sortedMurmurs.isEmpty)
          const Text(
            '還沒有散落的碎念。',
            style: TextStyle(
              fontSize: 13,
              color: AnsibleDesign.inkMuted,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final murmur in sortedMurmurs.take(5))
            _MurmurRow(murmur: murmur),
        const SizedBox(height: 20),
        const AnsibleSectionHead(zh: '來源 · LINEAGE', en: 'LOCAL CONTENT GRAPH'),
        const _LineagePreview(),
      ],
    );
  }

  int _compareNotes(ContentItem a, ContentItem b) {
    final byUpdated = _recentFirst
        ? b.updatedAt.compareTo(a.updatedAt)
        : a.updatedAt.compareTo(b.updatedAt);
    if (byUpdated != 0) return byUpdated;
    final byCreated = _recentFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }

  Future<void> _openCreateNoteEditor(BuildContext context) async {
    final repository = widget.contentItemRepository;
    final did = widget.authorDid;
    if (repository == null || did == null) return;

    final result = await Navigator.of(context).push<_CreateNoteResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateNoteEditorScreen(murmurs: widget.murmurs),
      ),
    );
    if (result == null) return;

    final now = DateTime.now().toUtc();
    final item = ContentItem(
      id: const Uuid().v4(),
      authorDid: did,
      mode: ContentMode.note,
      title: result.title,
      body: result.body,
      status: ContentStatus.active,
      visibility: result.visibility,
      createdAt: now,
      updatedAt: now,
      publishedAt: result.visibility == ContentVisibility.private ? null : now,
      localOnly: result.visibility == ContentVisibility.private,
    );
    await repository.create(item);
    if (result.visibility != ContentVisibility.private) {
      await widget.onPublishContentItem?.call(
        item,
        result.distributionPreference,
      );
    }
    await widget.onContentItemsChanged?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已建立筆記')));
  }
}

class _CreateNoteResult {
  const _CreateNoteResult({
    required this.title,
    required this.body,
    required this.visibility,
    required this.distributionPreference,
  });

  final String title;
  final String body;
  final ContentVisibility visibility;
  final DistributionPreference distributionPreference;
}

class _CreateNoteEditorScreen extends StatefulWidget {
  const _CreateNoteEditorScreen({
    required this.murmurs,
    this.initialTitle,
    this.initialBody,
    this.initialVisibility = ContentVisibility.private,
    this.initialDistributionPreference = DistributionPreference.localOnly,
  });

  @override
  State<_CreateNoteEditorScreen> createState() =>
      _CreateNoteEditorScreenState();

  final List<ContentItem> murmurs;
  final String? initialTitle;
  final String? initialBody;
  final ContentVisibility initialVisibility;
  final DistributionPreference initialDistributionPreference;
}

class _CreateNoteEditorScreenState extends State<_CreateNoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final _titleFocusNode = FocusNode();
  final _bodyFocusNode = FocusNode();
  bool _drawerOpen = true;
  bool _showErrors = false;
  bool _showFormatToolbar = false;
  late ContentVisibility _visibility;
  late DistributionPreference _distributionPreference;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _bodyController = NoteMarkdownEditingController(
      text: widget.initialBody ?? '',
    );
    _bodyController.addListener(_handleBodySelectionChanged);
    _bodyFocusNode.addListener(_handleBodySelectionChanged);
    _visibility = widget.initialVisibility;
    _distributionPreference = widget.initialDistributionPreference;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.removeListener(_handleBodySelectionChanged);
    _bodyController.dispose();
    _titleFocusNode.dispose();
    _bodyFocusNode.removeListener(_handleBodySelectionChanged);
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _handleBodySelectionChanged() {
    final selection = _bodyController.selection;
    final next =
        _bodyFocusNode.hasFocus &&
        selection.isValid &&
        !selection.isCollapsed &&
        _bodyController.text.isNotEmpty;
    if (next == _showFormatToolbar) return;
    setState(() => _showFormatToolbar = next);
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
                      focusNode: _titleFocusNode,
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
                    _EditorVisibilityRow(
                      visibility: _visibility,
                      distributionPreference: _distributionPreference,
                      onTap: _showVisibilitySheet,
                    ),
                    const SizedBox(height: 10),
                    DragTarget<ContentItem>(
                      key: const Key('note_body_drop_target'),
                      onWillAcceptWithDetails: (_) => true,
                      onAcceptWithDetails: (details) =>
                          _insertMurmur(details.data),
                      builder: (context, candidateData, rejectedData) {
                        final isHovering = candidateData.isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: isHovering
                              ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
                              : EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: isHovering
                                ? AnsibleDesign.accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isHovering
                                ? Border.all(
                                    color: AnsibleDesign.accent,
                                    width: 0.8,
                                  )
                                : null,
                          ),
                          child: TextField(
                            key: const Key('note_body_field'),
                            controller: _bodyController,
                            focusNode: _bodyFocusNode,
                            minLines: 9,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                              fontSize: AnsibleDesign.readingTextSize,
                              height: 1.8,
                              color: AnsibleDesign.ink,
                            ),
                            decoration: const InputDecoration(
                              filled: false,
                              hintText: '繼續寫下去，或從下方拖一個 murmur 進來……',
                              hintStyle: TextStyle(
                                color: AnsibleDesign.inkFaint,
                                fontSize: AnsibleDesign.readingTextSize,
                                height: 1.8,
                                fontStyle: FontStyle.italic,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        );
                      },
                    ),
                    if (bodyMissing) const _InlineError('請輸入內文'),
                  ],
                ),
              ),
            ),
            if (_showFormatToolbar)
              _EditorFormatToolbar(onFormat: _applyFormat),
            _EditorMurmurDrawer(
              open: _drawerOpen,
              murmurs: widget.murmurs,
              onInsertMurmur: _insertMurmur,
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
    Navigator.of(context).pop(
      _CreateNoteResult(
        title: title,
        body: body,
        visibility: _visibility,
        distributionPreference: _distributionPreference,
      ),
    );
  }

  Future<void> _showVisibilitySheet() async {
    final choice = await showContentDistributionSheet(
      context: context,
      current: ContentDistributionChoice(
        visibility: _visibility,
        distributionPreference: _distributionPreference,
      ),
      subjectLabel: '這篇 note',
    );
    if (choice == null || !mounted) return;
    setState(() {
      _visibility = choice.visibility;
      _distributionPreference = choice.distributionPreference;
    });
  }

  void _applyFormat(_EditorFormatAction action) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    if (!selection.isValid || selection.isCollapsed || text.isEmpty) return;
    final start = selection.start;
    final end = selection.end;
    final selected = text.substring(start, end);

    final formatted = switch (action) {
      _EditorFormatAction.bold => _FormattedText('**$selected**', 2),
      _EditorFormatAction.italic => _FormattedText('_${selected}_', 1),
      _EditorFormatAction.underline => _FormattedText('<u>$selected</u>', 3),
      _EditorFormatAction.quote => _FormattedText(
        selected.isEmpty
            ? '> '
            : selected.split('\n').map((line) => '> $line').join('\n'),
        2,
      ),
      _EditorFormatAction.heading => _FormattedText(
        selected.isEmpty ? '## ' : '## $selected',
        3,
      ),
      _EditorFormatAction.link => _FormattedText(
        selected.isEmpty ? '[](url)' : '[$selected](url)',
        1,
      ),
    };

    _bodyController.text = text.replaceRange(start, end, formatted.text);
    _bodyController.selection = TextSelection.collapsed(
      offset: start + formatted.text.length,
    );
    _bodyFocusNode.requestFocus();
    setState(() {});
  }

  void _insertMurmur(ContentItem murmur) {
    final quote = murmur.body
        .trim()
        .split('\n')
        .map((line) => '> $line')
        .join('\n');
    final insertion = _bodyController.text.trim().isEmpty
        ? '$quote\n\n'
        : '\n\n$quote\n\n';
    final selection = _bodyController.selection;
    final insertAt = selection.isValid
        ? selection.baseOffset.clamp(0, _bodyController.text.length)
        : _bodyController.text.length;
    final text = _bodyController.text;

    _bodyController.text = text.replaceRange(insertAt, insertAt, insertion);
    _bodyController.selection = TextSelection.collapsed(
      offset: insertAt + insertion.length,
    );
    _bodyFocusNode.requestFocus();
    setState(() {});
  }
}

class _FormattedText {
  const _FormattedText(this.text, this.emptyCursorOffset);

  final String text;
  final int emptyCursorOffset;
}

enum _EditorFormatAction { bold, italic, underline, quote, heading, link }

class _EditorVisibilityRow extends StatelessWidget {
  const _EditorVisibilityRow({
    required this.visibility,
    required this.distributionPreference,
    required this.onTap,
  });

  final ContentVisibility visibility;
  final DistributionPreference distributionPreference;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = contentVisibilityMeta(visibility);
    return InkWell(
      key: const Key('note_editor_visibility_chip'),
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Row(
        children: [
          AnsibleStatusChip(label: meta.label, dot: meta.dot),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _summary,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AnsibleDesign.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _summary {
    if (visibility == ContentVisibility.private) return '還沒讓任何人看見';
    return switch (distributionPreference) {
      DistributionPreference.nostr => '公開後會送到 Nostr relays',
      DistributionPreference.activityPub => '公開後會送到 ActivityPub relay',
      DistributionPreference.nostrAndActivityPub =>
        '公開後會送到 Nostr relays 與 ActivityPub relay',
      DistributionPreference.localOnly => '公開狀態，但暫不送出',
    };
  }
}

class _EditorFormatToolbar extends StatelessWidget {
  const _EditorFormatToolbar({required this.onFormat});

  final ValueChanged<_EditorFormatAction> onFormat;

  static const _tools = [
    _EditorFormatTool(
      key: Key('note_format_bold'),
      label: 'B',
      action: _EditorFormatAction.bold,
      weight: FontWeight.w700,
    ),
    _EditorFormatTool(
      key: Key('note_format_italic'),
      label: 'I',
      action: _EditorFormatAction.italic,
      style: FontStyle.italic,
    ),
    _EditorFormatTool(
      key: Key('note_format_underline'),
      label: 'U',
      action: _EditorFormatAction.underline,
      decoration: TextDecoration.underline,
    ),
    _EditorFormatTool(
      key: Key('note_format_quote'),
      label: '""',
      action: _EditorFormatAction.quote,
    ),
    _EditorFormatTool(
      key: Key('note_format_heading'),
      label: '§',
      action: _EditorFormatAction.heading,
    ),
    _EditorFormatTool(
      key: Key('note_format_link'),
      label: '↗',
      action: _EditorFormatAction.link,
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
          for (var i = 0; i < _tools.length; i++) ...[
            Expanded(
              child: _EditorFormatButton(
                tool: _tools[i],
                onTap: () => onFormat(_tools[i].action),
              ),
            ),
            if (i < _tools.length - 1)
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

class _EditorFormatButton extends StatelessWidget {
  const _EditorFormatButton({required this.tool, required this.onTap});

  final _EditorFormatTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      key: tool.key,
      onTap: onTap,
      radius: 22,
      child: Center(
        child: Text(
          tool.label,
          style: TextStyle(
            color: AnsibleDesign.paper,
            fontSize: 14,
            fontWeight: tool.weight,
            fontStyle: tool.style,
            decoration: tool.decoration,
            decorationColor: AnsibleDesign.paper,
          ),
        ),
      ),
    );
  }
}

class _EditorFormatTool {
  const _EditorFormatTool({
    required this.key,
    required this.label,
    required this.action,
    this.weight = FontWeight.w400,
    this.style = FontStyle.normal,
    this.decoration = TextDecoration.none,
  });

  final Key key;
  final String label;
  final _EditorFormatAction action;
  final FontWeight weight;
  final FontStyle style;
  final TextDecoration decoration;
}

class _EditorMurmurDrawer extends StatelessWidget {
  const _EditorMurmurDrawer({
    required this.open,
    required this.murmurs,
    required this.onInsertMurmur,
    required this.onToggle,
  });

  final bool open;
  final List<ContentItem> murmurs;
  final ValueChanged<ContentItem> onInsertMurmur;
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
                      itemBuilder: (context, index) => _EditorMurmurCard(
                        murmur: items[index],
                        onInsert: () => onInsertMurmur(items[index]),
                      ),
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
  const _EditorMurmurCard({required this.murmur, required this.onInsert});

  final ContentItem murmur;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) {
    return Draggable<ContentItem>(
      key: Key('note_editor_murmur_card_${murmur.id}'),
      data: murmur,
      feedback: Material(
        color: Colors.transparent,
        child: _EditorMurmurCardSurface(murmur: murmur, elevated: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.45,
        child: _EditorMurmurCardSurface(murmur: murmur),
      ),
      child: InkWell(
        onTap: onInsert,
        borderRadius: BorderRadius.circular(8),
        child: _EditorMurmurCardSurface(murmur: murmur),
      ),
    );
  }
}

class _EditorMurmurCardSurface extends StatelessWidget {
  const _EditorMurmurCardSurface({required this.murmur, this.elevated = false});

  final ContentItem murmur;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: AnsibleDesign.ink.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
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
    required this.murmurs,
    this.contentItemRepository,
    this.onContentItemsChanged,
    this.onPublishContentItem,
  });

  final ContentItem note;
  final List<ContentItem> murmurs;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;
  final Future<void> Function(
    ContentItem item,
    DistributionPreference preference,
  )?
  onPublishContentItem;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteDetailScreen(
              note: note,
              onEdit: contentItemRepository == null
                  ? null
                  : () => _openEditNoteEditor(context),
            ),
          ),
        );
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
            NoteMarkdownBody(
              note.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AnsibleDesign.previewTextSize,
                height: 1.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            _VisibilityMenu(
              note: note,
              contentItemRepository: contentItemRepository,
              onContentItemsChanged: onContentItemsChanged,
              onPublishContentItem: onPublishContentItem,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openEditNoteEditor(BuildContext context) async {
    final repository = contentItemRepository;
    if (repository == null) return;

    final result = await Navigator.of(context).push<_CreateNoteResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CreateNoteEditorScreen(
          murmurs: murmurs,
          initialTitle: note.title,
          initialBody: note.body,
          initialVisibility: note.visibility,
          initialDistributionPreference:
              ContentDistributionChoice.forVisibility(
                note.visibility,
              ).distributionPreference,
        ),
      ),
    );
    if (result == null) return;

    final now = DateTime.now().toUtc();
    final updated = ContentItem(
      id: note.id,
      authorDid: note.authorDid,
      mode: note.mode,
      title: result.title,
      body: result.body,
      status: note.status,
      visibility: result.visibility,
      createdAt: note.createdAt,
      updatedAt: now,
      subjectId: note.subjectId,
      publishedAt: result.visibility == ContentVisibility.private
          ? note.publishedAt
          : note.publishedAt ?? now,
      isDeleted: note.isDeleted,
      localOnly: result.visibility == ContentVisibility.private,
    );
    await repository.update(updated);
    if (result.visibility != ContentVisibility.private) {
      await onPublishContentItem?.call(updated, result.distributionPreference);
    }
    await onContentItemsChanged?.call();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已更新筆記')));
  }
}

class _VisibilityMenu extends StatelessWidget {
  const _VisibilityMenu({
    required this.note,
    this.contentItemRepository,
    this.onContentItemsChanged,
    this.onPublishContentItem,
  });

  final ContentItem note;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;
  final Future<void> Function(
    ContentItem item,
    DistributionPreference preference,
  )?
  onPublishContentItem;

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
    final choice = await showContentDistributionSheet(
      context: context,
      current: ContentDistributionChoice.forVisibility(note.visibility),
      subjectLabel: '這篇 note',
    );
    if (choice == null) return;
    if (!context.mounted) return;
    await _updateVisibility(context, choice);
  }

  Future<void> _updateVisibility(
    BuildContext context,
    ContentDistributionChoice choice,
  ) async {
    final visibility = choice.visibility;
    if (visibility == note.visibility || contentItemRepository == null) return;
    final now = DateTime.now().toUtc();

    final updated = ContentItem(
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
      publishedAt: visibility == ContentVisibility.private
          ? note.publishedAt
          : note.publishedAt ?? now,
      isDeleted: note.isDeleted,
      localOnly: visibility == ContentVisibility.private,
    );
    await contentItemRepository!.update(updated);
    if (visibility != ContentVisibility.private) {
      await onPublishContentItem?.call(updated, choice.distributionPreference);
    }
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
