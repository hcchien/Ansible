import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/messenger_sync_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'contact_picker_screen.dart';
import 'messenger_thread_screen.dart';

typedef ContactAvailabilityResolver =
    Future<MessengerAvailability> Function(ContactRecord contact);
typedef MessengerThreadBuilder =
    Widget Function(BuildContext context, ContactRecord contact);

class InboxScreen extends StatelessWidget {
  const InboxScreen({
    super.key,
    this.repository,
    this.contactRepository,
    this.messengerService,
    this.senderDid = 'did:plc:local',
    this.relayConfigured = true,
    this.resolveContactAvailability,
    this.resolveContactInput,
    this.threadBuilder,
  });

  final MessengerRepository? repository;
  final ContactRepository? contactRepository;
  final MessengerSyncService? messengerService;
  final String senderDid;
  final bool relayConfigured;
  final ContactAvailabilityResolver? resolveContactAvailability;
  final ContactInputResolver? resolveContactInput;
  final MessengerThreadBuilder? threadBuilder;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '收信匣', en: 'Inbox'),
      leadingLabel: text.t('backWorkspace'),
      child: repository == null
          ? const _EmptyInbox()
          : _InboxBody(
              repository: repository!,
              contactRepository: contactRepository,
              messengerService: messengerService,
              senderDid: senderDid,
              relayConfigured: relayConfigured,
              resolveContactAvailability: resolveContactAvailability,
              resolveContactInput: resolveContactInput,
              threadBuilder: threadBuilder,
            ),
    );
  }
}

class _InboxBody extends StatefulWidget {
  const _InboxBody({
    required this.repository,
    this.contactRepository,
    this.messengerService,
    required this.senderDid,
    required this.relayConfigured,
    this.resolveContactAvailability,
    this.resolveContactInput,
    this.threadBuilder,
  });

  final MessengerRepository repository;
  final ContactRepository? contactRepository;
  final MessengerSyncService? messengerService;
  final String senderDid;
  final bool relayConfigured;
  final ContactAvailabilityResolver? resolveContactAvailability;
  final ContactInputResolver? resolveContactInput;
  final MessengerThreadBuilder? threadBuilder;

  @override
  State<_InboxBody> createState() => _InboxBodyState();
}

class _InboxBodyState extends State<_InboxBody> {
  bool _composing = false;

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
          return _InboxError(message: userFacingError(context, error));
        }
        final previews = snapshot.data ?? const [];
        final onCompose = _canCompose ? _openComposer : null;
        if (previews.isEmpty) {
          return _EmptyInbox(onCompose: onCompose, composing: _composing);
        }
        return _ConversationList(
          previews: previews,
          onCompose: onCompose,
          composing: _composing,
          onAcceptRequest: _acceptRequest,
          onBlockRequest: _blockRequest,
        );
      },
    );
  }

  Future<List<_InboxConversationPreview>> _loadPreviews() async {
    final conversations = await widget.repository.conversationList();
    final previews = <_InboxConversationPreview>[];
    for (final conversation in conversations) {
      final messages = await widget.repository.messagesForConversation(
        conversation.conversationId,
      );
      final contact = await widget.contactRepository?.contactForDid(
        conversation.peerDid,
      );
      if (contact?.relationship == ContactRelationship.blocked ||
          contact?.trustState == ContactTrustState.blocked) {
        continue;
      }
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

  bool get _canCompose {
    return widget.contactRepository != null &&
        (widget.threadBuilder != null || widget.messengerService != null);
  }

  Future<void> _openComposer() async {
    final contactRepository = widget.contactRepository;
    if (contactRepository == null || _composing) return;
    if (!widget.relayConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SubpageL10n.of(context).t('relayRequired'))),
      );
      return;
    }
    setState(() => _composing = true);
    try {
      final contacts = await contactRepository.listContacts();
      final refreshed = <ContactRecord>[];
      for (final contact in contacts) {
        final availability = await _resolveAvailability(contact);
        final next = contact.copyWith(
          messengerAvailability: availability,
          updatedAt: DateTime.now().toUtc(),
        );
        if (next.messengerAvailability != contact.messengerAvailability) {
          await contactRepository.upsertContact(next);
        }
        refreshed.add(next);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (pickerContext) => ContactPickerScreen(
            contacts: refreshed,
            onResolveInput: widget.resolveContactInput == null
                ? null
                : _resolveContactInput,
            onContactSelected: (contact) {
              Navigator.of(pickerContext).pushReplacement(
                MaterialPageRoute(
                  builder: (threadContext) =>
                      _buildThread(threadContext, contact),
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  Future<ContactRecord> _resolveContactInput(String input) async {
    final resolver = widget.resolveContactInput!;
    final contactRepository = widget.contactRepository!;
    final contact = await resolver(input);
    final availability = await _resolveAvailability(contact);
    final resolved = contact.copyWith(
      messengerAvailability: availability,
      updatedAt: DateTime.now().toUtc(),
    );
    await contactRepository.upsertContact(resolved);
    return resolved;
  }

  Future<void> _acceptRequest(_InboxConversationPreview preview) async {
    final contact = preview.contact;
    final repository = widget.contactRepository;
    if (contact == null || repository == null) return;
    final now = DateTime.now().toUtc();
    await repository.upsertContact(
      contact.copyWith(
        relationship: ContactRelationship.conversation,
        source: 'conversation',
        trustState: ContactTrustState.known,
        updatedAt: now,
        lastResolvedAt: now,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _blockRequest(_InboxConversationPreview preview) async {
    final contact = preview.contact;
    final repository = widget.contactRepository;
    if (contact == null || repository == null) return;
    await repository.upsertContact(
      contact.copyWith(
        relationship: ContactRelationship.blocked,
        trustState: ContactTrustState.blocked,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<MessengerAvailability> _resolveAvailability(
    ContactRecord contact,
  ) async {
    final resolver = widget.resolveContactAvailability;
    if (resolver == null) return contact.messengerAvailability;
    return resolver(contact);
  }

  Widget _buildThread(BuildContext context, ContactRecord contact) {
    final builder = widget.threadBuilder;
    if (builder != null) return builder(context, contact);
    return MessengerThreadScreen(
      conversationId: contact.subjectDid,
      senderDid: widget.senderDid,
      messengerService: widget.messengerService!,
      contact: contact,
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.previews,
    this.onCompose,
    this.composing = false,
    this.onAcceptRequest,
    this.onBlockRequest,
  });

  final List<_InboxConversationPreview> previews;
  final VoidCallback? onCompose;
  final bool composing;
  final ValueChanged<_InboxConversationPreview>? onAcceptRequest;
  final ValueChanged<_InboxConversationPreview>? onBlockRequest;

  @override
  Widget build(BuildContext context) {
    final requests = previews.where((preview) => preview.isRequest).toList();
    final conversations = previews
        .where((preview) => !preview.isRequest)
        .toList();
    final rows = <Widget>[
      Builder(
        builder: (context) {
          final text = SubpageL10n.of(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _InboxHeading(
              label: text.t('inboxLabel'),
              title: text.t('messengerInboxHero'),
              subtitle: text.t('messengerInboxSubtitle'),
              onCompose: onCompose,
              composing: composing,
            ),
          );
        },
      ),
      if (requests.isNotEmpty) ...[
        Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AnsibleMonoLabel(
              SubpageL10n.of(context).t('messageRequests'),
            ),
          ),
        ),
        for (final request in requests)
          _ConversationRow(
            preview: request,
            onAcceptRequest: onAcceptRequest == null
                ? null
                : () => onAcceptRequest!(request),
            onBlockRequest: onBlockRequest == null
                ? null
                : () => onBlockRequest!(request),
          ),
      ],
      if (conversations.isNotEmpty && requests.isNotEmpty)
        const Divider(height: 1, thickness: 0.5, color: AnsibleDesign.ruleSoft),
      for (final preview in conversations) _ConversationRow(preview: preview),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 0.5,
        color: AnsibleDesign.ruleSoft,
      ),
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.preview,
    this.onAcceptRequest,
    this.onBlockRequest,
  });

  final _InboxConversationPreview preview;
  final VoidCallback? onAcceptRequest;
  final VoidCallback? onBlockRequest;

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
          if (preview.isRequest)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onAcceptRequest,
                  child: Text(SubpageL10n.of(context).t('acceptRequest')),
                ),
                TextButton(
                  onPressed: onBlockRequest,
                  child: Text(SubpageL10n.of(context).t('blockRequest')),
                ),
              ],
            )
          else
            Text(
              _shortTime(
                preview.conversation.lastMessageAt ?? latest?.createdAt,
              ),
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

  bool get isRequest {
    return contact?.relationship == ContactRelationship.invite ||
        contact?.source == 'message_request';
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({this.onCompose, this.composing = false});

  final VoidCallback? onCompose;
  final bool composing;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        _InboxHeading(
          label: text.t('inboxLabel'),
          title: text.t('inboxHero'),
          subtitle: text.t('inboxSubtitle'),
          onCompose: onCompose,
          composing: composing,
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

class _InboxHeading extends StatelessWidget {
  const _InboxHeading({
    required this.label,
    required this.title,
    required this.subtitle,
    this.onCompose,
    this.composing = false,
  });

  final String label;
  final String title;
  final String subtitle;
  final VoidCallback? onCompose;
  final bool composing;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(label),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
            ),
            if (onCompose != null)
              IconButton(
                key: const ValueKey('inbox-compose-button'),
                onPressed: composing ? null : onCompose,
                tooltip: text.t('newMessage'),
                icon: composing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_note_outlined),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            color: AnsibleDesign.inkFaint,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
