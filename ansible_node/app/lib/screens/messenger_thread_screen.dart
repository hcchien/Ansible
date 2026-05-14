import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../services/messenger_sync_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class MessengerThreadScreen extends StatefulWidget {
  const MessengerThreadScreen({
    super.key,
    required this.conversationId,
    required this.messengerService,
    this.senderDid = 'did:plc:local',
  });

  final String conversationId;
  final String senderDid;
  final MessengerSyncService messengerService;

  @override
  State<MessengerThreadScreen> createState() => _MessengerThreadScreenState();
}

class _MessengerThreadScreenState extends State<MessengerThreadScreen> {
  final _composer = TextEditingController();
  late Future<List<MessengerMessageRecord>> _messagesFuture;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messagesFuture = _loadMessages();
    _composer.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _composer
      ..removeListener(_onComposerChanged)
      ..dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    setState(() {});
  }

  Future<List<MessengerMessageRecord>> _loadMessages() {
    return widget.messengerService.messagesForConversation(
      widget.conversationId,
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.messengerService.sendText(
        senderDid: widget.senderDid,
        recipientDid: widget.conversationId,
        text: text,
      );
      _composer.clear();
      setState(() {
        _messagesFuture = _loadMessages();
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: 'MESSENGER',
      leadingLabel: text.t('backWorkspace'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.conversationId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
            ),
          ),
          if (_error != null) _ThreadErrorBanner(message: _error!),
          Expanded(
            child: FutureBuilder<List<MessengerMessageRecord>>(
              future: _messagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      text.t('emptyThread'),
                      style: const TextStyle(
                        color: AnsibleDesign.inkFaint,
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _MessageRow(message: messages[index]);
                  },
                );
              },
            ),
          ),
          _ComposerBar(
            controller: _composer,
            sending: _sending,
            onSend: _composer.text.trim().isEmpty || _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});

  final MessengerMessageRecord message;

  @override
  Widget build(BuildContext context) {
    if (message.status == MessengerMessageStatus.decryptFailed) {
      return const _DecryptFailedRow();
    }
    final outbound = message.direction == MessengerMessageDirection.outbound;
    return Align(
      alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: outbound ? AnsibleDesign.ink : AnsibleDesign.paperElev,
          border: Border.all(
            color: outbound ? AnsibleDesign.ink : AnsibleDesign.ruleSoft,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message.plaintext ?? '',
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: outbound ? AnsibleDesign.paper : AnsibleDesign.ink,
          ),
        ),
      ),
    );
  }
}

class _DecryptFailedRow extends StatelessWidget {
  const _DecryptFailedRow();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AnsibleDesign.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.t('messageDecryptFailed'),
              style: const TextStyle(
                fontSize: 12.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadErrorBanner extends StatelessWidget {
  const _ThreadErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.danger, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12.5, color: AnsibleDesign.danger),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('messenger-composer'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: text.t('messageComposerHint'),
                  isDense: true,
                  filled: true,
                  fillColor: AnsibleDesign.paperElev,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AnsibleDesign.ruleSoft,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('messenger-send-button'),
              tooltip: text.t('sendMessage'),
              onPressed: onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}
