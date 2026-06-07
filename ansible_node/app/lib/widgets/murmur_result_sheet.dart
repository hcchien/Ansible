import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_l10n.dart';
import '../services/ai/murmur_synthesis_service.dart';
import '../services/ai/vector_search_service.dart';
import '../theme/ansible_design.dart';

/// C·06 — Murmur result sheet shown after vector search.
class MurmurResultSheet extends StatefulWidget {
  const MurmurResultSheet({
    super.key,
    required this.results,
    required this.query,
    required this.synthesisService,
    required this.authorDid,
    required this.contentItemRepo,
    this.noteId,
    this.noteTitle,
    this.noteBody,
    this.contentRelationRepo,
    this.onNoteUpdated,
  });

  final List<MurmurSearchResult> results;
  final String query;
  final MurmurSynthesisService synthesisService;
  final String authorDid;
  final DriftContentItemRepository contentItemRepo;
  final String? noteId;
  final String? noteTitle;
  final String? noteBody;
  final DriftContentRelationRepository? contentRelationRepo;
  final VoidCallback? onNoteUpdated;

  @override
  State<MurmurResultSheet> createState() => _MurmurResultSheetState();
}

class _MurmurResultSheetState extends State<MurmurResultSheet> {
  late Set<String> _selectedIds;
  String? _draft;
  bool _synthesising = false;
  bool _inserting = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.results.map((r) => r.murmur.id).toSet();
    // Trigger synthesis after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _synthesize();
    });
  }

  List<ContentItem> get _selectedMurmurs => widget.results
      .where((r) => _selectedIds.contains(r.murmur.id))
      .map((r) => r.murmur)
      .toList();

  Future<void> _synthesize() async {
    final selected = _selectedMurmurs;
    if (selected.isEmpty) return;
    setState(() {
      _synthesising = true;
      _draft = null;
    });
    try {
      final draft = await widget.synthesisService.synthesize(
        selectedMurmurs: selected,
        noteTitle: widget.noteTitle,
        noteBodyExcerpt: widget.noteBody,
      );
      if (mounted) setState(() => _draft = draft);
    } catch (e) {
      if (mounted) {
        setState(() => _draft = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(zh: '草擬失敗：$e', en: 'Draft failed: $e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _synthesising = false);
    }
  }

  Future<void> _insertIntoNote() async {
    final draft = _draft;
    if (draft == null || draft.isEmpty) return;
    setState(() => _inserting = true);
    try {
      final now = DateTime.now().toUtc();
      final uuid = const Uuid();
      String noteId;

      if (widget.noteId != null) {
        // Append to existing note
        noteId = widget.noteId!;
        final existing = await widget.contentItemRepo.getById(noteId);
        if (existing != null) {
          final updatedBody = existing.body.isEmpty
              ? draft
              : '${existing.body}\n\n$draft';
          await widget.contentItemRepo.update(
            ContentItem(
              id: existing.id,
              authorDid: existing.authorDid,
              mode: existing.mode,
              title: existing.title,
              body: updatedBody,
              status: existing.status,
              visibility: existing.visibility,
              createdAt: existing.createdAt,
              updatedAt: now,
              subjectId: existing.subjectId,
              publishedAt: existing.publishedAt,
              isDeleted: existing.isDeleted,
              localOnly: existing.localOnly,
            ),
          );
        }
      } else {
        // Create new note from personal board
        noteId = uuid.v4();
        await widget.contentItemRepo.create(
          ContentItem(
            id: noteId,
            authorDid: widget.authorDid,
            mode: ContentMode.note,
            title: widget.query,
            body: draft,
            status: ContentStatus.active,
            visibility: ContentVisibility.private,
            createdAt: now,
            updatedAt: now,
            localOnly: true,
          ),
        );
      }

      // Create ContentRelations for each selected murmur
      final relRepo = widget.contentRelationRepo;
      if (relRepo != null) {
        for (final murmur in _selectedMurmurs) {
          await relRepo.create(
            ContentRelation(
              id: uuid.v4(),
              fromContentItemId: murmur.id,
              toContentItemId: noteId,
              relationType: RelationType.references,
              createdByDid: widget.authorDid,
              createdAt: now,
              localOnly: true,
            ),
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onNoteUpdated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(zh: '編入失敗：$e', en: 'Insert failed: $e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _inserting = false);
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return context.uiCopy(zh: '${diff.inDays}天前', en: '${diff.inDays}d ago');
    }
    return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.results.length;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AnsibleDesign.paper,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: AnsibleDesign.ruleSoft,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AnsibleDesign.ochre,
                        ),
                        child: const Center(
                          child: AnsibleMark(
                            size: 18,
                            color: AnsibleDesign.paper,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.uiCopy(
                            zh: 'AI · 找到 $count 段',
                            en: 'AI · $count found',
                          ),
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AnsibleDesign.rule,
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          context.uiCopy(zh: '本地 · LOCAL', en: 'LOCAL'),
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9,
                            color: AnsibleDesign.inkFaint,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Scrollable body
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    children: [
                      // Intro
                      Text(
                        context.uiCopy(
                          zh: '主題：${widget.query}。從你的 murmur 找到 $count 段。要編入哪些？',
                          en: 'Topic: ${widget.query}. Found $count matching murmurs. Which ones should be inserted?',
                        ),
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 13,
                          color: AnsibleDesign.inkMuted,
                          height: 1.55,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Checklist
                      if (widget.results.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            context.uiCopy(
                              zh: '沒有找到相關的 murmur。',
                              en: 'No related murmurs found.',
                            ),
                            style: const TextStyle(
                              fontFamily: AnsibleDesign.serif,
                              fontSize: 13,
                              color: AnsibleDesign.inkFaint,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        for (final result in widget.results)
                          _MurmurCheckRow(
                            result: result,
                            selected: _selectedIds.contains(result.murmur.id),
                            onToggle: () {
                              setState(() {
                                if (_selectedIds.contains(result.murmur.id)) {
                                  _selectedIds.remove(result.murmur.id);
                                } else {
                                  _selectedIds.add(result.murmur.id);
                                }
                              });
                            },
                            formatDate: _formatDate,
                          ),

                      const SizedBox(height: 16),

                      // Section kicker
                      const _SectionKicker(zh: 'AI 草擬', en: 'AI DRAFT'),

                      const SizedBox(height: 10),

                      // Draft preview
                      _DraftBox(draft: _draft, synthesising: _synthesising),

                      const SizedBox(height: 16),

                      // Buttons
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: (_synthesising || _inserting)
                                ? null
                                : _synthesize,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AnsibleDesign.ink,
                              side: const BorderSide(
                                color: AnsibleDesign.rule,
                                width: 0.5,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              context.uiCopy(zh: '重新草擬', en: 'Redraft'),
                              style: const TextStyle(
                                fontFamily: AnsibleDesign.serif,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  (_inserting ||
                                      _synthesising ||
                                      _draft == null)
                                  ? null
                                  : _insertIntoNote,
                              style: FilledButton.styleFrom(
                                backgroundColor: AnsibleDesign.ink,
                                foregroundColor: AnsibleDesign.paper,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _inserting
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AnsibleDesign.paper,
                                      ),
                                    )
                                  : Text(
                                      context.uiCopy(
                                        zh: '編入 note →',
                                        en: 'Insert into note →',
                                      ),
                                      style: const TextStyle(
                                        fontFamily: AnsibleDesign.serif,
                                        fontSize: 13,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Footer note
                      Text(
                        context.uiCopy(
                          zh: '原本的 murmur 不會被刪除。',
                          en: 'Original murmurs will not be deleted.',
                        ),
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MurmurCheckRow extends StatelessWidget {
  const _MurmurCheckRow({
    required this.result,
    required this.selected,
    required this.onToggle,
    required this.formatDate,
  });

  final MurmurSearchResult result;
  final bool selected;
  final VoidCallback onToggle;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
                activeColor: AnsibleDesign.ink,
                side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.murmur.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 13.5,
                      color: AnsibleDesign.ink,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatDate(result.murmur.createdAt),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9,
                      color: AnsibleDesign.inkFaint,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionKicker extends StatelessWidget {
  const _SectionKicker({required this.zh, required this.en});

  final String zh;
  final String en;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          context.uiCopy(zh: zh, en: en),
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 11,
            letterSpacing: 1.4,
            color: AnsibleDesign.inkFaint,
          ),
        ),
        const SizedBox(width: 6),
        if (context.usesChineseUi) ...[
          const SizedBox(width: 6),
          Text(
            '· $en',
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11,
              letterSpacing: 1.4,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class _DraftBox extends StatelessWidget {
  const _DraftBox({required this.draft, required this.synthesising});

  final String? draft;
  final bool synthesising;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
      ),
      child: synthesising
          ? Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  context.uiCopy(zh: '草擬中…', en: 'Drafting...'),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          : draft != null
          ? Text(
              draft!,
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 13.5,
                color: AnsibleDesign.ink,
                height: 1.6,
              ),
            )
          : Text(
              context.uiCopy(
                zh: '選擇 murmur 後自動草擬。',
                en: 'Choose murmurs to draft automatically.',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 13,
                color: AnsibleDesign.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
    );
  }
}
