import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/content_visibility_sheet.dart';
import '../widgets/note_markdown_text.dart';
import 'note_detail_screen.dart';

part 'note_workspace_screen.editor.dart';
part 'note_workspace_screen.list.dart';

class NoteWorkspaceScreen extends StatefulWidget {
  const NoteWorkspaceScreen({
    super.key,
    this.authorDid,
    this.notes = const [],
    this.murmurs = const [],
    this.contentItemRepository,
    this.onContentItemsChanged,
    this.onPublicPostSaved,
    this.onPublishContentItem,
    this.onSummonAI,
    this.openCreateEditorOnStart = false,
  });

  final String? authorDid;
  final List<ContentItem> notes;
  final List<ContentItem> murmurs;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;
  final Future<void> Function()? onPublicPostSaved;
  final Future<void> Function(
    ContentItem item,
    DistributionPreference preference,
  )?
  onPublishContentItem;

  /// Called to open the AI agent search sheet, optionally anchored to a note.
  final Future<void> Function({
    String? noteId,
    String? noteTitle,
    String? noteBody,
  })?
  onSummonAI;
  final bool openCreateEditorOnStart;

  @override
  State<NoteWorkspaceScreen> createState() => _NoteWorkspaceScreenState();
}

class _NoteWorkspaceScreenState extends State<NoteWorkspaceScreen> {
  bool _recentFirst = true;
  bool _initialCreateEditorOpened = false;

  @override
  void initState() {
    super.initState();
    _scheduleInitialCreateEditor();
  }

  @override
  void didUpdateWidget(NoteWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleInitialCreateEditor();
  }

  void _scheduleInitialCreateEditor() {
    if (!widget.openCreateEditorOnStart || _initialCreateEditorOpened) return;
    _initialCreateEditorOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openCreateNoteEditor(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sortedNotes = [...widget.notes]..sort(_compareNotes);
    final sortedMurmurs = [...widget.murmurs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final onSummonAI = widget.onSummonAI;
    final content = ListView(
      padding: const EdgeInsets.only(bottom: 0),
      children: [
        Row(
          children: [
            Expanded(
              child: AnsibleSectionHead(
                zh: l10n.workingNotes,
                en: 'WORKING NOTES',
              ),
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
              label: Text(_recentFirst ? l10n.newest : l10n.oldest),
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
              label: Text(l10n.newNote),
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
        AnsibleSectionHead(
          zh: l10n.looseMurmurs,
          en: 'LOOSE MURMURS',
          action: l10n.drawInAction,
        ),
        if (sortedMurmurs.isEmpty)
          Text(
            l10n.noLooseMurmursYet,
            style: const TextStyle(
              fontSize: 13,
              color: AnsibleDesign.inkMuted,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          for (final murmur in sortedMurmurs.take(5))
            _MurmurRow(murmur: murmur),
        const SizedBox(height: 20),
        AnsibleSectionHead(zh: l10n.lineage, en: 'LOCAL CONTENT GRAPH'),
        const _LineagePreview(),
        // Extra space so content isn't hidden behind summon strip
        if (onSummonAI != null) const SizedBox(height: 72),
      ],
    );

    if (onSummonAI == null) return content;

    return Column(
      children: [
        Expanded(child: content),
        // Summon strip — B·04 design
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
            ),
            color: AnsibleDesign.paper,
          ),
          child: GestureDetector(
            onTap: () => onSummonAI(),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.ink,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: AnsibleDesign.paper,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.uiCopy(
                      zh: '想從之前的 murmur 找東西延伸這篇？',
                      en: 'Find earlier murmurs to extend this note?',
                    ),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 13,
                      color: AnsibleDesign.inkMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: AnsibleDesign.inkFaint,
                ),
              ],
            ),
          ),
        ),
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
        builder: (_) =>
            _CreateNoteEditorScreen(murmurs: widget.murmurs, authorDid: did),
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
    if (result.visibility == ContentVisibility.public) {
      await widget.onPublicPostSaved?.call();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.noteCreated)));
  }
}
