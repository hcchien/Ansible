import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../services/blocked_author_store.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class BlockedListScreen extends StatefulWidget {
  const BlockedListScreen({
    super.key,
    required this.repository,
    required this.ownerDid,
    this.blockedAuthorStore = const BlockedAuthorStore(),
  });

  final ContactRepository repository;
  final String ownerDid;
  final BlockedAuthorStore blockedAuthorStore;

  @override
  State<BlockedListScreen> createState() => _BlockedListScreenState();
}

class _BlockedListScreenState extends State<BlockedListScreen> {
  late Future<List<_BlockedEntry>> _blockedContacts;

  @override
  void initState() {
    super.initState();
    _blockedContacts = _loadBlockedContacts();
  }

  Future<List<_BlockedEntry>> _loadBlockedContacts() async {
    final contacts = await widget.repository.listContacts();
    final contactsByDid = {
      for (final contact in contacts) contact.subjectDid: contact,
    };
    final blockedDids = contacts
        .where(
          (contact) =>
              contact.relationship == ContactRelationship.blocked ||
              contact.trustState == ContactTrustState.blocked ||
              contact.messengerAvailability == MessengerAvailability.blocked,
        )
        .map((contact) => contact.subjectDid)
        .toSet();
    blockedDids.addAll(await widget.blockedAuthorStore.load(widget.ownerDid));

    final entries = blockedDids.map((did) {
      final contact = contactsByDid[did];
      return _BlockedEntry(
        subjectDid: did,
        label: contact?.label ?? did,
        contact: contact,
      );
    }).toList();
    entries.sort((a, b) => a.label.compareTo(b.label));
    return entries;
  }

  Future<void> _unblock(_BlockedEntry entry) async {
    await widget.blockedAuthorStore.unblock(widget.ownerDid, entry.subjectDid);
    final contact = entry.contact;
    if (contact != null) {
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
    }
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
      child: FutureBuilder<List<_BlockedEntry>>(
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
          final contacts = snapshot.data ?? const <_BlockedEntry>[];
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
                entry: contact,
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
  const _BlockedContactRow({required this.entry, required this.onUnblock});

  final _BlockedEntry entry;
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
                  entry.label,
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
                  entry.subjectDid,
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

class _BlockedEntry {
  const _BlockedEntry({
    required this.subjectDid,
    required this.label,
    required this.contact,
  });

  final String subjectDid;
  final String label;
  final ContactRecord? contact;
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
