import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Full-screen composer for a forum reply (new or edit), styled to the app's
/// design system to match [ThreadComposerScreen]. Pops the trimmed content
/// string on submit, or null on cancel — the same contract the old
/// PostFormDialog used.
class PostComposerScreen extends StatefulWidget {
  const PostComposerScreen({super.key, this.initialContent, this.authorDid});

  final String? initialContent;

  /// Shown in the footer for parity with the other composers. Optional.
  final String? authorDid;

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  late final TextEditingController _controller;
  String? _error;

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
    Navigator.of(context).pop<String>(content);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(isEdit: _isEdit, onCancel: () => Navigator.of(context).pop(), onDone: _submit),
            if (_error != null) _ErrorBanner(message: _error!),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: TextField(
                  key: const Key('post_composer_body_field'),
                  controller: _controller,
                  autofocus: true,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontSize: AnsibleDesign.readingTextSize,
                    height: 1.8,
                    color: AnsibleDesign.ink,
                  ),
                  decoration: InputDecoration(
                    filled: false,
                    hintText: context.uiCopy(
                      zh: '輸入貼文內容',
                      en: 'Write your reply',
                    ),
                    hintStyle: const TextStyle(
                      color: AnsibleDesign.inkFaint,
                      fontSize: AnsibleDesign.readingTextSize,
                      height: 1.8,
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
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            label: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
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
          Text(
            isEdit
                ? context.uiCopy(zh: '編輯貼文 · EDIT', en: 'EDIT POST')
                : context.uiCopy(zh: '發表貼文 · REPLY', en: 'NEW POST'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 14),
          FilledButton(
            key: const Key('post_composer_done_button'),
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: AnsibleDesign.paperElev,
              foregroundColor: AnsibleDesign.ink,
              side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 34),
            ),
            child: Text(
              context.uiCopy(zh: '發表', en: 'Post'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.did, required this.characterCount});

  final String? did;
  final int characterCount;

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
          if (did != null && did!.isNotEmpty) ...[
            const Icon(
              Icons.fingerprint_rounded,
              size: 14,
              color: AnsibleDesign.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                did!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            context.uiCopy(zh: '$characterCount 字', en: '$characterCount chars'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 0.7,
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
