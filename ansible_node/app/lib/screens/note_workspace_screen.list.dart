part of 'note_workspace_screen.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.noNotesYet,
            style: const TextStyle(
              fontSize: 18,
              color: AnsibleDesign.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.noNotesDescription,
            style: const TextStyle(
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
    ).showSnackBar(SnackBar(content: Text(context.l10n.noteUpdated)));
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
    final meta = contentVisibilityMeta(context, note.visibility);
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
      subjectLabel: context.l10n.noteSubjectLabel,
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
    ).showSnackBar(SnackBar(content: Text(context.l10n.visibilityUpdated)));
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
        children: [
          Text(
            context.l10n.lineageDescription,
            style: const TextStyle(
              color: AnsibleDesign.inkMuted,
              height: 1.55,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
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
