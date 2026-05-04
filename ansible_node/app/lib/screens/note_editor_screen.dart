import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';

import '../services/ops_dispatch_service.dart';

class NoteEditorScreen extends StatefulWidget {
  final String authorDid;
  final String boardId;
  final String threadId;
  final String threadTitle;
  final OpsQueueRepository opsQueueRepo;
  final OpsDispatchService? opsDispatchService;

  const NoteEditorScreen({
    super.key,
    required this.authorDid,
    required this.boardId,
    required this.threadId,
    required this.threadTitle,
    required this.opsQueueRepo,
    this.opsDispatchService,
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
      final entry = CrdtOpBuilder.createPost(
        authorDid: widget.authorDid,
        entityId: const Uuid().v4(),
        boardId: widget.boardId,
        threadId: widget.threadId,
        content: content,
      );
      final dispatchService = widget.opsDispatchService;
      if (dispatchService == null) {
        await widget.opsQueueRepo.enqueue(entry);
      } else {
        await dispatchService.signAndEnqueue(entry);
        await dispatchService.flushPending();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已加入發送佇列'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = '發送失敗：$e';
      });
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
