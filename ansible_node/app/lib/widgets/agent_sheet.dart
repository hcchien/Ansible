import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/murmur_synthesis_service.dart';
import '../services/ai/vector_search_service.dart';
import '../theme/ansible_design.dart';
import 'murmur_result_sheet.dart';

/// C·05 — Agent search sheet.
/// Shown when the user taps the ElixAIDot or the summon strip in a note.
class AgentSheet extends StatefulWidget {
  const AgentSheet({
    super.key,
    required this.searchService,
    required this.authorDid,
    required this.contentItemRepo,
    required this.aiProvider,
    required this.aiProviderType,
    this.noteId,
    this.noteTitle,
    this.noteBody,
    this.contentRelationRepo,
    this.onNoteUpdated,
  });

  final VectorSearchService searchService;
  final String authorDid;
  final DriftContentItemRepository contentItemRepo;
  final AiProvider aiProvider;
  final AiProviderType aiProviderType;
  final String? noteId;
  final String? noteTitle;
  final String? noteBody;
  final DriftContentRelationRepository? contentRelationRepo;
  final VoidCallback? onNoteUpdated;

  @override
  State<AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<AgentSheet> {
  final TextEditingController _queryController = TextEditingController();
  bool _recentOnly = true;
  bool _loading = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() => _loading = true);
    try {
      final since = _recentOnly
          ? DateTime.now().subtract(const Duration(days: 14))
          : null;
      final results = await widget.searchService.search(
        query: query,
        topK: 20,
        since: since,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close this sheet
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AnsibleDesign.paper,
        showDragHandle: false,
        isScrollControlled: true,
        builder: (_) => MurmurResultSheet(
          results: results,
          query: query,
          synthesisService: MurmurSynthesisService(
            widget.aiProvider,
            providerType: widget.aiProviderType,
          ),
          noteId: widget.noteId,
          noteTitle: widget.noteTitle,
          noteBody: widget.noteBody,
          authorDid: widget.authorDid,
          contentItemRepo: widget.contentItemRepo,
          contentRelationRepo: widget.contentRelationRepo,
          onNoteUpdated: widget.onNoteUpdated,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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

            // Top row: AI badge + title + X
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.ink,
                  ),
                  child: const Center(
                    child: AnsibleMark(size: 18, color: AnsibleDesign.paper),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.uiCopy(
                      zh: 'AI · 從你的 murmur 找',
                      en: 'AI · Search your murmurs',
                    ),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  color: AnsibleDesign.inkMuted,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Body text
            Text(
              context.uiCopy(
                zh: '我會先檢查隱私範圍；遠端 AI 不會自動接收私人內容。',
                en: 'I will check privacy boundaries first; remote AI will not automatically receive private content.',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AnsibleDesign.inkMuted,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 16),

            // Input field
            TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 15,
                color: AnsibleDesign.ink,
              ),
              decoration: InputDecoration(
                hintText: context.uiCopy(
                  zh: '想找什麼主題？',
                  en: 'What topic are you looking for?',
                ),
                hintStyle: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 15,
                  color: AnsibleDesign.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
                filled: true,
                fillColor: AnsibleDesign.paperElev,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AnsibleDesign.rule,
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AnsibleDesign.rule,
                    width: 0.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AnsibleDesign.ink,
                    width: 0.8,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),

            // Chips row: 最近兩週 / 全部
            Row(
              children: [
                _FilterChip(
                  label: context.uiCopy(zh: '最近兩週', en: 'Last 2 weeks'),
                  active: _recentOnly,
                  onTap: () => setState(() => _recentOnly = true),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.uiCopy(zh: '全部', en: 'All'),
                  active: !_recentOnly,
                  onTap: () => setState(() => _recentOnly = false),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Footer row: privacy note + 尋找 button
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.uiCopy(
                      zh: '不會用來訓練。不會離開這台手機。',
                      en: 'Not used for training. Does not leave this phone.',
                    ),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AnsibleDesign.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  style: FilledButton.styleFrom(
                    backgroundColor: AnsibleDesign.ink,
                    foregroundColor: AnsibleDesign.paper,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AnsibleDesign.paper,
                          ),
                        )
                      : Text(
                          context.uiCopy(zh: '尋找 →', en: 'Search →'),
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 14,
                          ),
                        ),
                ),
              ],
            ),

            SizedBox(height: 24 + viewInsets.bottom),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AnsibleDesign.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AnsibleDesign.ink : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 13,
            color: active ? AnsibleDesign.paper : AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
  }
}
