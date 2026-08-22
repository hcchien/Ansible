import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../services/canonical_identity_store.dart';
import '../murmur_screen.dart';
import '../note_workspace_screen.dart';
import '../edit_profile_screen.dart';
import 'home_types.dart';

/// Full-screen Circle (圈內) pushed via Navigator for compose flows.
class CircleFullScreen extends StatefulWidget {
  const CircleFullScreen({
    super.key,
    required this.did,
    required this.db,
    required this.initialTab,
    required this.contentItems,
    required this.contentItemRepository,
    required this.murmurReferenceCounts,
    required this.onContentItemsChanged,
    required this.onPublishContentItem,
    required this.onSummonAiForNote,
    required this.openNoteEditorOnStart,
  });

  final String did;
  final AppDatabase db;
  final CircleTab initialTab;
  final List<ContentItem> contentItems;
  final ContentItemRepository contentItemRepository;
  final Map<String, int> murmurReferenceCounts;
  final Future<void> Function() onContentItemsChanged;
  final Future<void> Function(ContentItem, DistributionPreference)
  onPublishContentItem;
  final Future<void> Function({
    String? noteId,
    String? noteTitle,
    String? noteBody,
  })
  onSummonAiForNote;
  final bool openNoteEditorOnStart;

  @override
  State<CircleFullScreen> createState() => _CircleFullScreenState();
}

class _CircleFullScreenState extends State<CircleFullScreen> {
  late CircleTab _tab;
  late List<ContentItem> _contentItems;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _contentItems = [...widget.contentItems];
  }

  Future<void> _handleContentItemsChanged() async {
    await widget.onContentItemsChanged();
    final latest = await widget.contentItemRepository.list(
      authorDid: widget.did,
    );
    if (!mounted) return;
    setState(() => _contentItems = latest);
  }

  Future<void> _offerPublicProfileAfterPost() async {
    final self = await DriftContactRepository(
      widget.db,
    ).contactForDid(widget.did);
    final canonical = await const SecureCanonicalIdentityStore().load();
    final isPublic =
        (self?.handle?.trim().isNotEmpty ?? false) ||
        (self?.displayName?.trim().isNotEmpty ?? false) ||
        (canonical?.did == widget.did && canonical!.handle.trim().isNotEmpty);
    if (isPublic || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '想讓讀者也能找到你？建立公開 profile。',
            en: 'Want readers to find you? Create a public profile.',
          ),
        ),
        action: SnackBarAction(
          label: context.uiCopy(zh: '設定', en: 'SET UP'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditProfileScreen(db: widget.db, did: widget.did),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                    color: dark ? AnsibleDesign.darkInk : AnsibleDesign.ink,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tab == CircleTab.murmur ? 'Murmur' : 'Note',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: dark
                                ? AnsibleDesign.darkInk
                                : AnsibleDesign.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tab == CircleTab.murmur
                              ? context.uiCopy(
                                  zh: '說一段不用想太完整的話',
                                  en: 'Say something unfinished',
                                )
                              : context.uiCopy(
                                  zh: '個人版 · note',
                                  en: 'Personal · note',
                                ),
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            color: dark
                                ? AnsibleDesign.darkInkFaint
                                : AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: switch (_tab) {
                  CircleTab.murmur => MurmurScreen(
                    authorDid: widget.did,
                    contentItemRepository: widget.contentItemRepository,
                    recentMurmurs: _contentItems
                        .where((i) => i.mode == ContentMode.murmur)
                        .toList(),
                    murmurReferenceCounts: widget.murmurReferenceCounts,
                    onSaved: _handleContentItemsChanged,
                    onPublicPostSaved: _offerPublicProfileAfterPost,
                    onPublishContentItem: widget.onPublishContentItem,
                  ),
                  CircleTab.notes => NoteWorkspaceScreen(
                    authorDid: widget.did,
                    notes: _contentItems
                        .where((i) => i.mode == ContentMode.note)
                        .toList(),
                    murmurs: _contentItems
                        .where((i) => i.mode == ContentMode.murmur)
                        .toList(),
                    contentItemRepository: widget.contentItemRepository,
                    onContentItemsChanged: _handleContentItemsChanged,
                    onPublicPostSaved: _offerPublicProfileAfterPost,
                    onPublishContentItem: widget.onPublishContentItem,
                    onSummonAI: ({noteId, noteTitle, noteBody}) =>
                        widget.onSummonAiForNote(
                          noteId: noteId,
                          noteTitle: noteTitle,
                          noteBody: noteBody,
                        ),
                    openCreateEditorOnStart: widget.openNoteEditorOnStart,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
