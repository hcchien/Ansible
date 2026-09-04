import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/author_label.dart';
import '../widgets/mention_picker.dart';

class PostComposerResult {
  const PostComposerResult({
    required this.content,
    this.mentionDids = const [],
  });

  final String content;
  final List<String> mentionDids;
}

/// Full-screen composer for a forum reply (new or edit), styled to the app's
/// design system to match [ThreadComposerScreen]. Pops a [PostComposerResult]
/// containing trimmed content and explicitly resolved mention DIDs, or null on
/// cancel.
class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({
    super.key,
    this.initialContent,
    this.authorDid,
    this.mentionSearch,
  });

  final String? initialContent;

  /// Shown in the footer for parity with the other composers. Optional.
  final String? authorDid;
  final MentionActorSearch? mentionSearch;

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  late final TextEditingController _controller;
  final MentionDraft _mentions = MentionDraft();
  String? _error;
  bool _mentionPickerOpen = false;

  bool get _isEdit => widget.initialContent != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      setState(
        () => _error = context.uiCopy(zh: '請輸入內容', en: 'Content is required'),
      );
      return;
    }
    Navigator.of(context).pop(
      PostComposerResult(
        content: content,
        mentionDids: _mentions.activeDids(
          content,
          excludingDid: widget.authorDid,
        ),
      ),
    );
  }

  void _onComposerChanged(String _) {
    if (_isEdit || _mentionPickerOpen) return;
    final value = _controller.value;
    final cursor = value.selection.baseOffset;
    if (!value.selection.isCollapsed || cursor <= 0) return;
    if (value.text[cursor - 1] != '@') return;
    if (cursor > 1 && !RegExp(r'\s').hasMatch(value.text[cursor - 2])) return;

    _mentionPickerOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _pickMention(replaceStart: cursor - 1, replaceEnd: cursor);
      _mentionPickerOpen = false;
    });
  }

  Future<void> _pickMention({int? replaceStart, int? replaceEnd}) async {
    final actor = await showMentionPicker(
      context: context,
      search: widget.mentionSearch,
      excludingDid: widget.authorDid,
    );
    if (!mounted || actor == null) return;
    final token = _mentions.record(actor);
    insertMention(
      _controller,
      actor,
      token: token,
      replaceStart: replaceStart,
      replaceEnd: replaceEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              isEdit: _isEdit,
              onCancel: () => Navigator.of(context).pop(),
              onDone: _submit,
            ),
            if (_error != null) _ErrorBanner(message: _error!),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: TextField(
                  key: const Key('post_composer_body_field'),
                  controller: _controller,
                  onChanged: _onComposerChanged,
                  autofocus: true,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  cursorColor: AnsibleDesign.accent,
                  cursorWidth: 2,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 22,
                    height: 1.5,
                    color: AnsibleDesign.ink,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    hintText: context.uiCopy(
                      zh: '輸入貼文內容',
                      en: 'Write your reply',
                    ),
                    hintStyle: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      color: AnsibleDesign.inkFaint,
                      fontSize: 22,
                      height: 1.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            _Footer(
              did: widget.authorDid,
              characterCount: _controller.text.characters.length,
              onMention: _isEdit ? null : () => _pickMention(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isEdit,
    required this.onCancel,
    required this.onDone,
  });

  final bool isEdit;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
                style: TextButton.styleFrom(
                  foregroundColor: AnsibleDesign.inkMuted,
                  textStyle: const TextStyle(
                    fontFamily: AnsibleDesign.sans,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          Text(
            isEdit
                ? context.uiCopy(zh: '編輯貼文 · EDIT', en: 'EDIT POST')
                : context.uiCopy(zh: '發表貼文 · REPLY', en: 'NEW POST'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11,
              color: AnsibleDesign.inkMuted,
              letterSpacing: 2.4,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('post_composer_done_button'),
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: AnsibleDesign.paperElev,
                  foregroundColor: AnsibleDesign.ink,
                  side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(
                  context.uiCopy(zh: '發表', en: 'Post'),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.did,
    required this.characterCount,
    this.onMention,
  });

  final String? did;
  final int characterCount;
  final VoidCallback? onMention;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 10),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(
          top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (onMention != null) ...[
            TextButton.icon(
              key: const Key('post_composer_mention_button'),
              onPressed: onMention,
              icon: const Icon(Icons.alternate_email, size: 17),
              label: Text(context.uiCopy(zh: '提及', en: 'Mention')),
              style: TextButton.styleFrom(
                foregroundColor: AnsibleDesign.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (did != null && did!.isNotEmpty) ...[
            const Icon(
              Icons.fingerprint_rounded,
              size: 18,
              color: AnsibleDesign.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AuthorLabel(
                did: did!,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 13,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            context.uiCopy(
              zh: '$characterCount 字',
              en: '$characterCount chars',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 13,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 4, 22, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.danger.withValues(alpha: 0.10),
        border: Border.all(color: AnsibleDesign.danger.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AnsibleDesign.danger,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AnsibleDesign.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
