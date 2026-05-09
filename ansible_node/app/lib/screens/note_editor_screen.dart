import 'package:flutter/material.dart';
import 'package:ansible_vc/ansible_vc.dart';

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
  bool _drawerOpen = true;
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
                    const Text(
                      '編輯中 · EDITING',
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9.5,
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
                          fontSize: 9.5,
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
                    const _VisibilityRow(),
                    const SizedBox(height: 6),
                    _BodyField(
                      controller: _contentController,
                      enabled: !_isSending,
                      onChanged: () => setState(() {}),
                    ),
                    const _EmbeddedMurmur(),
                    const _ContinuationHint(),
                  ],
                ),
              ),
            ),
            const _FormatToolbar(),
            _MurmurDrawer(
              open: _drawerOpen,
              onToggle: () => setState(() => _drawerOpen = !_drawerOpen),
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
            label: const Text('取消'),
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
                : const Text(
                    '完成',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: AnsibleDesign.spore, size: 5),
        SizedBox(width: 8),
        Text(
          '草稿保留 · 本機',
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 9.5,
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
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        hintText: '末日松茸採集',
        hintStyle: TextStyle(
          color: AnsibleDesign.inkFaint,
          fontSize: 28,
          fontStyle: FontStyle.normal,
          fontWeight: FontWeight.w500,
        ),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AnsibleDesign.accent, width: 1),
        ),
        contentPadding: EdgeInsets.fromLTRB(0, 4, 0, 8),
      ),
    );
  }
}

class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _VisibilityChip(),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '還沒讓任何人看見',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AnsibleDesign.inkFaint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: AnsibleDesign.inkMuted, size: 4),
          SizedBox(width: 5),
          Text(
            'private',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkMuted,
              letterSpacing: 1,
            ),
          ),
        ],
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
        fontSize: 15.5,
        height: 1.8,
        color: AnsibleDesign.ink,
      ),
      decoration: const InputDecoration(
        filled: false,
        hintText: '一朵一朵地撿，慢慢撿。林下不是空的——只是用看不見的方式生長著。',
        hintStyle: TextStyle(
          color: AnsibleDesign.inkFaint,
          fontSize: 15.5,
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

class _EmbeddedMurmur extends StatelessWidget {
  const _EmbeddedMurmur();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          left: BorderSide(color: AnsibleDesign.accent, width: 1.5),
        ),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '松茸喜歡的是被擾動過、卻沒被毀掉的林子。',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: AnsibleDesign.ink,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Text(
                'MURMUR · 04.27 14:36',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 8.5,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(width: 8),
              _Dot(color: AnsibleDesign.inkFaint, size: 3),
              SizedBox(width: 8),
              Text(
                '編入此處',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 8.5,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 1.1,
                ),
              ),
              Spacer(),
              Text(
                '取消編入',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 8.5,
                  color: AnsibleDesign.inkMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinuationHint extends StatelessWidget {
  const _ContinuationHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        '繼續寫下去，或從下方拖一個 murmur 進來……',
        style: TextStyle(
          fontSize: 15.5,
          height: 1.8,
          color: AnsibleDesign.inkFaint,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar();

  static const _tools = [
    _FormatTool('B', FontWeight.w700, FontStyle.normal, TextDecoration.none),
    _FormatTool('I', FontWeight.w400, FontStyle.italic, TextDecoration.none),
    _FormatTool(
      'U',
      FontWeight.w400,
      FontStyle.normal,
      TextDecoration.underline,
    ),
    _FormatTool('""', FontWeight.w400, FontStyle.normal, TextDecoration.none),
    _FormatTool('§', FontWeight.w400, FontStyle.normal, TextDecoration.none),
    _FormatTool('↗', FontWeight.w400, FontStyle.normal, TextDecoration.none),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AnsibleDesign.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AnsibleDesign.ink.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _tools.length; i++) ...[
            Expanded(child: _FormatButton(tool: _tools[i])),
            if (i < _tools.length - 1)
              Container(
                width: 0.5,
                height: 18,
                color: AnsibleDesign.paper.withValues(alpha: 0.16),
              ),
          ],
        ],
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({required this.tool});

  final _FormatTool tool;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        tool.label,
        style: TextStyle(
          color: AnsibleDesign.paper,
          fontSize: 14,
          fontWeight: tool.weight,
          fontStyle: tool.style,
          decoration: tool.decoration,
          decorationColor: AnsibleDesign.paper,
        ),
      ),
    );
  }
}

class _FormatTool {
  const _FormatTool(this.label, this.weight, this.style, this.decoration);

  final String label;
  final FontWeight weight;
  final FontStyle style;
  final TextDecoration decoration;
}

class _MurmurDrawer extends StatelessWidget {
  const _MurmurDrawer({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: const Key('note_editor_murmur_drawer'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          top: BorderSide(color: AnsibleDesign.rule, width: 0.5),
          left: BorderSide(color: AnsibleDesign.rule, width: 0.5),
          right: BorderSide(color: AnsibleDesign.rule, width: 0.5),
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AnsibleDesign.rule,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '編入 · DRAW IN',
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9.5,
                      color: AnsibleDesign.inkFaint,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: AnsibleDesign.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                itemBuilder: (context, index) {
                  final murmur = _murmurs[index];
                  return _MurmurCard(murmur: murmur);
                },
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemCount: _murmurs.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _MurmurCard extends StatelessWidget {
  const _MurmurCard({required this.murmur});

  final _MurmurPreview murmur;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: murmur.used ? 0.62 : 1,
      child: Container(
        width: 168,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AnsibleDesign.paper,
          border: Border.all(
            color: murmur.used ? AnsibleDesign.accent : AnsibleDesign.rule,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${murmur.quote ? 'QUOTE' : 'MURMUR'} · ${murmur.date}',
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    color: AnsibleDesign.inkFaint,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  murmur.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AnsibleDesign.ink,
                    fontStyle: murmur.quote
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ],
            ),
            if (murmur.used)
              const Positioned(
                top: 0,
                right: 0,
                child: Text(
                  '已編入',
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8,
                    color: AnsibleDesign.accent,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
          ],
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
            '$characterCount 字',
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

class _MurmurPreview {
  const _MurmurPreview({
    required this.date,
    required this.text,
    this.used = false,
    this.quote = false,
  });

  final String date;
  final String text;
  final bool used;
  final bool quote;
}

const _murmurs = [
  _MurmurPreview(date: '04.27', text: '松茸喜歡的是被擾動過……', used: true),
  _MurmurPreview(date: '04.27', text: '不必修復的鬆動感'),
  _MurmurPreview(
    date: '04.26',
    text: '“The mushroom at the end of the world.”',
    quote: true,
  ),
  _MurmurPreview(date: '04.24', text: '為什麼是「擾動過卻沒被毀掉」'),
  _MurmurPreview(date: '04.22', text: 'Tsing 的 patches'),
  _MurmurPreview(date: '04.21', text: '林下不是空的——'),
];
