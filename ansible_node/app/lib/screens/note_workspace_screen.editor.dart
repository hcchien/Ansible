part of 'note_workspace_screen.dart';

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
    final l10n = context.l10n;
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
                  IconButton(
                    key: const Key('note_editor_cancel_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AnsibleDesign.inkMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _EditorDot(color: AnsibleDesign.spore, size: 5),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.draftLocal,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AnsibleDesign.mono,
                                fontSize: 11,
                                color: AnsibleDesign.inkFaint,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const Key('note_editor_done_button'),
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
                    child: Text(
                      l10n.done,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.editing,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 11,
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
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: l10n.noteTitleHint,
                        hintStyle: const TextStyle(
                          color: AnsibleDesign.inkFaint,
                          fontSize: 28,
                          fontStyle: FontStyle.normal,
                          fontWeight: FontWeight.w500,
                        ),
                        border: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.ruleSoft,
                            width: 0.5,
                          ),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.ruleSoft,
                            width: 0.5,
                          ),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: AnsibleDesign.accent,
                            width: 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      ),
                    ),
                    if (titleMissing) _InlineError(l10n.noteTitleRequired),
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
                            decoration: InputDecoration(
                              filled: false,
                              hintText: l10n.noteBodyHint,
                              hintStyle: const TextStyle(
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
                    if (bodyMissing) _InlineError(l10n.noteBodyRequired),
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
      subjectLabel: context.l10n.noteSubjectLabel,
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

    final nextText = text.replaceRange(start, end, formatted.text);
    _bodyController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + formatted.text.length),
      composing: TextRange.empty,
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
    final text = _bodyController.text;
    final (start, end) = selection.isValid
        ? (
            selection.start.clamp(0, text.length),
            selection.end.clamp(0, text.length),
          )
        : (text.length, text.length);
    final insertAt = start < end ? start : end;
    final replaceEnd = start < end ? end : start;
    final nextText = text.replaceRange(insertAt, replaceEnd, insertion);
    _bodyController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: insertAt + insertion.length),
      composing: TextRange.empty,
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
              _summary(context),
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

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    if (visibility == ContentVisibility.private) return l10n.notePrivateSummary;
    return switch (distributionPreference) {
      DistributionPreference.nostr => l10n.noteNostrSummary,
      DistributionPreference.activityPub => l10n.noteActivityPubSummary,
      DistributionPreference.nostrAndActivityPub => l10n.noteBothSummary,
      DistributionPreference.localOnly => l10n.noteLocalPublicSummary,
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
                  Text(
                    context.l10n.drawIn,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 11,
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
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          context.l10n.noMurmursToDraw,
                          style: const TextStyle(
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
