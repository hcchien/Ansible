import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, this.repository, this.contactRepository});

  final MessengerRepository? repository;
  final ContactRepository? contactRepository;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: 'INBOX',
      leadingLabel: text.t('backWorkspace'),
      child: repository == null
          ? const _EmptyInbox()
          : _InboxBody(
              repository: repository!,
              contactRepository: contactRepository,
            ),
    );
  }
}

class _InboxBody extends StatelessWidget {
  const _InboxBody({required this.repository, this.contactRepository});

  final MessengerRepository repository;
  final ContactRepository? contactRepository;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_InboxConversationPreview>>(
      future: _loadPreviews(),
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
        final error = snapshot.error;
        if (error != null) {
          return _InboxError(message: error.toString());
        }
        final previews = snapshot.data ?? const [];
        if (previews.isEmpty) return const _EmptyInbox();
        return _ConversationList(previews: previews);
      },
    );
  }

  Future<List<_InboxConversationPreview>> _loadPreviews() async {
    final conversations = await repository.conversationList();
    final previews = <_InboxConversationPreview>[];
    for (final conversation in conversations) {
      final messages = await repository.messagesForConversation(
        conversation.conversationId,
      );
      final contact = await contactRepository?.contactForDid(
        conversation.peerDid,
      );
      final latest = messages.isEmpty ? null : messages.last;
      previews.add(
        _InboxConversationPreview(
          conversation: conversation,
          latestMessage: latest,
          contact: contact,
        ),
      );
    }
    return previews;
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({required this.previews});

  final List<_InboxConversationPreview> previews;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      itemCount: previews.length + 1,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 0.5,
        color: AnsibleDesign.ruleSoft,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnsibleMonoLabel(text.t('inboxLabel')),
                const SizedBox(height: 4),
                Text(
                  text.t('messengerInboxHero'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('messengerInboxSubtitle'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AnsibleDesign.inkFaint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          );
        }
        return _ConversationRow(preview: previews[index - 1]);
      },
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.preview});

  final _InboxConversationPreview preview;

  @override
  Widget build(BuildContext context) {
    final latest = preview.latestMessage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const AnsibleGlyphBox(glyph: '✉'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.contact?.label ?? preview.conversation.peerDid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _previewText(context, latest),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _shortTime(preview.conversation.lastMessageAt ?? latest?.createdAt),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              letterSpacing: 1.1,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  String _previewText(BuildContext context, MessengerMessageRecord? latest) {
    if (latest == null) return '—';
    if (latest.status == MessengerMessageStatus.decryptFailed) {
      return SubpageL10n.of(context).t('messageDecryptFailed');
    }
    return latest.plaintext ?? 'ciphertext';
  }

  String _shortTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Text(message, style: const TextStyle(color: AnsibleDesign.danger)),
    );
  }
}

class _InboxConversationPreview {
  final MessengerConversationRecord conversation;
  final MessengerMessageRecord? latestMessage;
  final ContactRecord? contact;

  const _InboxConversationPreview({
    required this.conversation,
    required this.latestMessage,
    this.contact,
  });
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        AnsibleMonoLabel(text.t('inboxLabel')),
        const SizedBox(height: 4),
        Text(
          text.t('inboxHero'),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: AnsibleDesign.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text.t('inboxSubtitle'),
          style: const TextStyle(
            fontSize: 12.5,
            color: AnsibleDesign.inkFaint,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          decoration: BoxDecoration(
            color: AnsibleDesign.paperElev,
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const AnsibleGlyphBox(glyph: '◐'),
              const SizedBox(height: 14),
              Text(
                text.t('emptyInbox'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text.t('emptyInboxBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
