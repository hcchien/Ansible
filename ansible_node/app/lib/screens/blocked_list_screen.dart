import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class BlockedListScreen extends StatefulWidget {
  const BlockedListScreen({super.key, required this.repository});

  final ContactRepository repository;

  @override
  State<BlockedListScreen> createState() => _BlockedListScreenState();
}

class _BlockedListScreenState extends State<BlockedListScreen> {
  late Future<List<ContactRecord>> _blockedContacts;

  @override
  void initState() {
    super.initState();
    _blockedContacts = _loadBlockedContacts();
  }

  Future<List<ContactRecord>> _loadBlockedContacts() async {
    final contacts = await widget.repository.listContacts();
    return contacts
        .where(
          (contact) =>
              contact.relationship == ContactRelationship.blocked ||
              contact.trustState == ContactTrustState.blocked ||
              contact.messengerAvailability == MessengerAvailability.blocked,
        )
        .toList(growable: false);
  }

  Future<void> _unblock(ContactRecord contact) async {
    final now = DateTime.now().toUtc();
    await widget.repository.upsertContact(
      contact.copyWith(
        relationship: contact.relationship == ContactRelationship.blocked
            ? ContactRelationship.unknown
            : contact.relationship,
        trustState: contact.trustState == ContactTrustState.blocked
            ? ContactTrustState.unverified
            : contact.trustState,
        messengerAvailability:
            contact.messengerAvailability == MessengerAvailability.blocked
            ? MessengerAvailability.unresolved
            : contact.messengerAvailability,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(() {
      _blockedContacts = _loadBlockedContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: text.t('blockedListTitleCaps'),
      leadingLabel: text.t('backSettings'),
      child: FutureBuilder<List<ContactRecord>>(
        future: _blockedContacts,
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
          final contacts = snapshot.data ?? const <ContactRecord>[];
          if (contacts.isEmpty) return const _EmptyBlockedList();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
            itemCount: contacts.length + 1,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              thickness: 0.5,
              color: AnsibleDesign.ruleSoft,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AnsibleMonoLabel(text.t('blockedListLabel')),
                );
              }
              final contact = contacts[index - 1];
              return _BlockedContactRow(
                contact: contact,
                onUnblock: () => _unblock(contact),
              );
            },
          );
        },
      ),
    );
  }
}

class _BlockedContactRow extends StatelessWidget {
  const _BlockedContactRow({required this.contact, required this.onUnblock});

  final ContactRecord contact;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const AnsibleGlyphBox(glyph: '⊘'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.label,
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
                  contact.subjectDid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUnblock,
            child: Text(text.t('unblockContact')),
          ),
        ],
      ),
    );
  }
}

class _EmptyBlockedList extends StatelessWidget {
  const _EmptyBlockedList();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        AnsibleMonoLabel(text.t('blockedListLabel')),
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
              const AnsibleGlyphBox(glyph: '⊘'),
              const SizedBox(height: 14),
              Text(
                text.t('blockedListEmpty'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
