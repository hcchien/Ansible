import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class ContactPickerScreen extends StatelessWidget {
  const ContactPickerScreen({
    super.key,
    required this.contacts,
    required this.onContactSelected,
  });

  final List<ContactRecord> contacts;
  final ValueChanged<ContactRecord> onContactSelected;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: text.t('contactsTitle').toUpperCase(),
      leadingLabel: text.t('backWorkspace'),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        itemCount: contacts.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          thickness: 0.5,
          color: AnsibleDesign.ruleSoft,
        ),
        itemBuilder: (context, index) {
          final contact = contacts[index];
          final enabled =
              contact.messengerAvailability == MessengerAvailability.available;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: enabled,
            title: Text(
              contact.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              contact.handle ?? contact.shortDid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _availabilityLabel(text, contact.messengerAvailability),
              style: TextStyle(
                fontSize: 12,
                color: enabled ? AnsibleDesign.ink : AnsibleDesign.inkFaint,
              ),
            ),
            onTap: enabled ? () => onContactSelected(contact) : null,
          );
        },
      ),
    );
  }

  String _availabilityLabel(
    SubpageL10n text,
    MessengerAvailability availability,
  ) {
    return switch (availability) {
      MessengerAvailability.available => text.t('contactAvailable'),
      MessengerAvailability.noDevices => text.t('contactNoDevices'),
      MessengerAvailability.noPreKeys => text.t('contactNoPreKeys'),
      MessengerAvailability.blocked => text.t('contactBlocked'),
      MessengerAvailability.unresolved => text.t('contactUnresolved'),
      MessengerAvailability.relayUnavailable => text.t(
        'contactRelayUnavailable',
      ),
    };
  }
}
