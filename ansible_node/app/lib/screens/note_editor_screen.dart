import 'package:flutter/material.dart';
import 'package:ansible_vc/ansible_vc.dart';

import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/atproto_client.dart';
import '../theme/ansible_design.dart';

/// V2.0 note editor — signs a [LexiconPost] record via [LexiconSigner] and
/// publishes it directly to the Relay with [AtProtoClient.createRecord].
///
/// Replaces the V1.x CrdtOpBuilder + OpsDispatchService path.
class NoteEditorScreen extends StatefulWidget {
  final String authorDid;
  final String boardId;
  final String threadId;
  final String threadTitle;

  /// V2.0 transport — required for XRPC createRecord.
  final AtProtoClient atProtoClient;

  /// V2.0 signer — defaults to [LexiconSignerImpl] when not provided.
  final LexiconSigner? lexiconSigner;

  const NoteEditorScreen({
    super.key,
    required this.authorDid,
    required this.boardId,
    required this.threadId,
    required this.threadTitle,
    required this.atProtoClient,
    this.lexiconSigner,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isSending = false;
  String? _errorMessage;

  LexiconSigner get _signer => widget.lexiconSigner ?? LexiconSignerImpl();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  String get _truncatedDid {
    final did = widget.authorDid;
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  Future<void> _send() async {
    final content = _composedContent;
    if (content.isEmpty) {
      setState(
        () =>
            _errorMessage = _copy(zh: '內容不得為空', en: 'Content cannot be empty'),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      // 1. Build the Lexicon record map.
      final record = LexiconPost(
        text: content,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        threadId: widget.threadId.isNotEmpty ? widget.threadId : null,
        boardId: widget.boardId.isNotEmpty ? widget.boardId : null,
      ).toJson();

      // 2. Sign with Ed25519 over DAG-CBOR (or dev stub if Rust unavailable).
      final signed = await _signer.sign(record, authorDid: widget.authorDid);

      // 3. Publish to Relay via XRPC createRecord.
      await widget.atProtoClient.createRecord(
        CreateRecordRequest(
          repo: widget.authorDid,
          collection: LexiconPost.type,
          record: signed.record,
          commitSig: signed.commitSigHex,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_copy(zh: '已發佈', en: 'Published')),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } on AtProtoException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = _formatAtProtoError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = userFacingError(context, e);
      });
    }
  }

  String get _composedContent {
    final title = _titleController.text.trim();
    final body = _contentController.text.trim();
    if (title.isEmpty) return body;
    if (body.isEmpty) return title;
    return '$title\n\n$body';
  }

  String _formatAtProtoError(AtProtoException e) {
    switch (e.error) {
      case 'unregistered_did':
        return _copy(
          zh: '身份驗證失敗，請重新登入。',
          en: 'Identity verification failed. Sign in again.',
        );
      case 'invalid_sig':
        return _copy(
          zh: '簽名驗證失敗，請重新嘗試。',
          en: 'Signature verification failed. Try again.',
        );
      case 'rate_limited':
        return _copy(
          zh: '發送速率過快，請稍後再試。',
          en: 'Sending too quickly. Try again later.',
        );
      case 'missing_fields':
        return _copy(
          zh: '資料格式錯誤，請重新嘗試。',
          en: 'Data format is invalid. Try again.',
        );
      default:
        return _copy(zh: '發送失敗 (${e.error})', en: 'Send failed (${e.error})');
    }
  }

  String _copy({required String zh, required String en}) {
    return context.uiCopy(zh: zh, en: en);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            _EditorTopBar(
              isSending: _isSending,
              onCancel: () => Navigator.of(context).pop(),
              onDone: _send,
            ),
            if (_errorMessage != null)
              _ErrorBanner(
                message: _errorMessage!,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
            if (widget.threadTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                child: Row(
                  children: [
                    Text(
                      context.uiCopy(zh: '編輯中 · EDITING', en: 'EDITING'),
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 11,
                        color: AnsibleDesign.inkFaint,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        widget.threadTitle,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 11,
                          color: AnsibleDesign.inkFaint,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TitleField(
                      controller: _titleController,
                      enabled: !_isSending,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _BodyField(
                      controller: _contentController,
                      enabled: !_isSending,
                      onChanged: () => setState(() {}),
                    ),
                    const _ContinuationHint(),
                  ],
                ),
              ),
            ),
            _EditorFooter(
              did: _truncatedDid,
              characterCount: _composedContent.length,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.isSending,
    required this.onCancel,
    required this.onDone,
  });

  final bool isSending;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: isSending ? null : onCancel,
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
          const _AutoSaveStatus(),
          const SizedBox(width: 14),
          FilledButton(
            key: const Key('note_editor_done_button'),
            onPressed: isSending ? null : onDone,
            style: FilledButton.styleFrom(
              backgroundColor: AnsibleDesign.paperElev,
              foregroundColor: AnsibleDesign.ink,
              disabledBackgroundColor: AnsibleDesign.paperDeep,
              disabledForegroundColor: AnsibleDesign.inkFaint,
              side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 34),
            ),
            child: isSending
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AnsibleDesign.accent,
                    ),
                  )
                : Text(
                    context.uiCopy(zh: '完成', en: 'Done'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AutoSaveStatus extends StatelessWidget {
  const _AutoSaveStatus();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Dot(color: AnsibleDesign.spore, size: 5),
        const SizedBox(width: 8),
        Text(
          context.uiCopy(zh: '草稿保留 · 本機', en: 'Draft saved · Local'),
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 11,
            color: AnsibleDesign.inkFaint,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('note_editor_title_field'),
      controller: controller,
      autofocus: true,
      enabled: enabled,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
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
        hintText: context.uiCopy(zh: '筆記標題', en: 'Note title'),
        hintStyle: const TextStyle(
          color: AnsibleDesign.inkFaint,
          fontSize: 28,
          fontStyle: FontStyle.normal,
          fontWeight: FontWeight.w500,
        ),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.accent, width: 1),
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      ),
    );
  }
}

class _BodyField extends StatelessWidget {
  const _BodyField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('note_editor_body_field'),
      controller: controller,
      enabled: enabled,
      minLines: 7,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      onChanged: (_) => onChanged(),
      style: const TextStyle(
        fontSize: AnsibleDesign.readingTextSize,
        height: 1.8,
        color: AnsibleDesign.ink,
      ),
      decoration: InputDecoration(
        filled: false,
        hintText: context.uiCopy(zh: '寫下筆記內容', en: 'Write note content'),
        hintStyle: const TextStyle(
          color: AnsibleDesign.inkFaint,
          fontSize: AnsibleDesign.readingTextSize,
          height: 1.8,
          fontStyle: FontStyle.normal,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

class _ContinuationHint extends StatelessWidget {
  const _ContinuationHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        context.uiCopy(zh: '繼續寫下去……', en: 'Keep writing...'),
        style: const TextStyle(
          fontSize: AnsibleDesign.readingTextSize,
          height: 1.8,
          color: AnsibleDesign.inkFaint,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({required this.did, required this.characterCount});

  final String did;
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
          const Icon(
            Icons.fingerprint_rounded,
            size: 14,
            color: AnsibleDesign.accent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              did,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ),
          Text(
            context.uiCopy(
              zh: '$characterCount 字',
              en: '$characterCount chars',
            ),
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
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 4, 22, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
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
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AnsibleDesign.danger,
            ),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

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
