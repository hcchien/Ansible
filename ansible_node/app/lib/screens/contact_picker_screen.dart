import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

typedef ContactInputResolver = Future<ContactRecord> Function(String input);

class ContactPickerScreen extends StatefulWidget {
  const ContactPickerScreen({
    super.key,
    required this.contacts,
    required this.onContactSelected,
    this.onResolveInput,
  });

  final List<ContactRecord> contacts;
  final ValueChanged<ContactRecord> onContactSelected;
  final ContactInputResolver? onResolveInput;

  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  late final TextEditingController _inputController;
  late List<ContactRecord> _contacts;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _contacts = [...widget.contacts];
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _resolveInput() async {
    final resolver = widget.onResolveInput;
    if (resolver == null || _resolving) return;
    final input = _inputController.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final contact = await resolver(input);
      setState(() {
        _contacts = [
          contact,
          ..._contacts.where((item) => item.subjectDid != contact.subjectDid),
        ];
        _inputController.clear();
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: text.t('contactsTitle').toUpperCase(),
      leadingLabel: text.t('backWorkspace'),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        itemCount: _contacts.length + 1,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          thickness: 0.5,
          color: AnsibleDesign.ruleSoft,
        ),
        itemBuilder: (context, index) {
          if (index == 0) return _searchBox(text: text);
          final contact = _contacts[index - 1];
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
            onTap: enabled ? () => widget.onContactSelected(contact) : null,
          );
        },
      ),
    );
  }

  Widget _searchBox({required SubpageL10n text}) {
    if (widget.onResolveInput == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('contact-id-input'),
                  controller: _inputController,
                  decoration: InputDecoration(
                    hintText: text.t('contactIdHint'),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _resolveInput(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _resolving ? null : _resolveInput,
                tooltip: text.t('searchId'),
                icon: _resolving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_outlined),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AnsibleDesign.danger, fontSize: 12),
            ),
          ],
        ],
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
