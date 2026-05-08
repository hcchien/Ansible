import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

class NoteWorkspaceScreen extends StatelessWidget {
  const NoteWorkspaceScreen({
    super.key,
    this.notes = const [],
    this.murmurs = const [],
    this.contentItemRepository,
    this.onContentItemsChanged,
  });

  final List<ContentItem> notes;
  final List<ContentItem> murmurs;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onContentItemsChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const AnsibleSectionHead(zh: '草地', en: 'WORKING NOTES', action: '↓ 最近'),
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
    return Container(
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
    final meta = _visibilityMeta(note.visibility);
    final chip = AnsibleStatusChip(label: meta.label, dot: meta.dot);
    if (contentItemRepository == null) return chip;

    return PopupMenuButton<ContentVisibility>(
      tooltip: '設定可見性',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (visibility) => _updateVisibility(context, visibility),
      itemBuilder: (_) => const [
        PopupMenuItem(value: ContentVisibility.private, child: Text('私人')),
        PopupMenuItem(value: ContentVisibility.public, child: Text('公開')),
      ],
      child: chip,
    );
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

({String label, Color dot}) _visibilityMeta(ContentVisibility visibility) {
  return switch (visibility) {
    ContentVisibility.private => (
      label: 'PRIVATE',
      dot: AnsibleDesign.inkMuted,
    ),
    ContentVisibility.unlisted => (label: 'CIRCLE', dot: AnsibleDesign.spore),
    ContentVisibility.public => (label: 'PUBLIC', dot: AnsibleDesign.accent),
  };
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
