import 'package:flutter/material.dart';
import 'package:ansible_vc/ansible_vc.dart';

import '../services/atproto_client.dart';

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
  final TextEditingController _contentController = TextEditingController();
  bool _isSending = false;
  String? _errorMessage;

  static const _bgDeep = Color(0xFF050915);
  static const _bgLight = Color(0xFF0B1220);
  static const _accent = Color(0xFFFF9F43);

  LexiconSigner get _signer => widget.lexiconSigner ?? LexiconSignerImpl();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  String get _truncatedDid {
    final did = widget.authorDid;
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  Future<void> _send() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorMessage = '內容不得為空');
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
      ).toJson();

      // 2. Sign with Ed25519 over DAG-CBOR (or dev stub if Rust unavailable).
      final signed = await _signer.sign(
        record,
        authorDid: widget.authorDid,
      );

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
        const SnackBar(
          content: Text('已發佈'),
          duration: Duration(seconds: 2),
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
        _errorMessage = '發送失敗：$e';
      });
    }
  }

  String _formatAtProtoError(AtProtoException e) {
    switch (e.error) {
      case 'unregistered_did':
        return '身份驗證失敗，請重新登入。';
      case 'invalid_sig':
        return '簽名驗證失敗，請重新嘗試。';
      case 'rate_limited':
        return '發送速率過快，請稍後再試。';
      case 'missing_fields':
        return '資料格式錯誤，請重新嘗試。';
      default:
        return '發送失敗 (${e.error})';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: _bgLight,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '關閉',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '新貼文',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (widget.threadTitle.isNotEmpty)
              Text(
                widget.threadTitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        actions: [
          if (_isSending)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.send_rounded, color: _accent),
              tooltip: '發送',
              onPressed: _send,
            ),
        ],
      ),
      body: Column(
        children: [
          // Error banner
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.redAccent.withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => setState(() => _errorMessage = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          // Editor
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _contentController,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                enabled: !_isSending,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  hintText: '輸入內容...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          // Bottom status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _bgLight,
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.fingerprint, size: 14, color: _accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _truncatedDid,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_contentController.text.length} 字',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
