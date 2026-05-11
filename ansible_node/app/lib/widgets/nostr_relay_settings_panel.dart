import 'dart:async';

import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import 'ansible_screen_chrome.dart';

class NostrRelaySettingsPanel extends StatefulWidget {
  final List<NostrRelayPreference> relays;
  final FutureOr<void> Function(List<NostrRelayPreference> relays) onChanged;

  const NostrRelaySettingsPanel({
    super.key,
    required this.relays,
    required this.onChanged,
  });

  @override
  State<NostrRelaySettingsPanel> createState() =>
      _NostrRelaySettingsPanelState();
}

class _NostrRelaySettingsPanelState extends State<NostrRelaySettingsPanel> {
  final TextEditingController _urlController = TextEditingController();
  bool _newRelayRead = true;
  bool _newRelayWrite = true;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          text.t('nostrRelays'),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
            ),
          ),
          child: Column(
            children: [
              _buildAddRelayRow(),
              const Divider(height: 0.5, color: AnsibleDesign.ruleSoft),
              if (widget.relays.isEmpty)
                const _EmptyRelayRow()
              else
                for (var i = 0; i < widget.relays.length; i += 1)
                  _RelayPreferenceRow(
                    index: i,
                    relay: widget.relays[i],
                    isLast: i == widget.relays.length - 1,
                    onReadChanged: (value) => _updateRelay(
                      i,
                      read: value,
                      write: widget.relays[i].write,
                    ),
                    onWriteChanged: (value) => _updateRelay(
                      i,
                      read: widget.relays[i].read,
                      write: value,
                    ),
                    onRemove: () => _removeRelay(i),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddRelayRow() {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('nostr_relay_url_field'),
                  controller: _urlController,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'wss://relay.example',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addRelay(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('nostr_add_relay_button'),
                tooltip: text.t('addRelay'),
                icon: const Icon(Icons.add, size: 18),
                onPressed: _addRelay,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _RelayFlagToggle(
                key: const Key('nostr_new_relay_read'),
                label: 'READ',
                value: _newRelayRead,
                onChanged: (value) => setState(() => _newRelayRead = value),
              ),
              const SizedBox(width: 10),
              _RelayFlagToggle(
                key: const Key('nostr_new_relay_write'),
                label: 'WRITE',
                value: _newRelayWrite,
                onChanged: (value) => setState(() => _newRelayWrite = value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addRelay() {
    final url = _urlController.text.trim();
    if (url.isEmpty || (!_newRelayRead && !_newRelayWrite)) return;
    final next = _mergeRelay([
      ...widget.relays,
      NostrRelayPreference(
        url: url,
        read: _newRelayRead,
        write: _newRelayWrite,
      ),
    ]);
    _urlController.clear();
    widget.onChanged(next);
  }

  void _updateRelay(int index, {required bool read, required bool write}) {
    if (!read && !write) return;
    final next = [...widget.relays];
    next[index] = NostrRelayPreference(
      url: widget.relays[index].url,
      read: read,
      write: write,
    );
    widget.onChanged(next);
  }

  void _removeRelay(int index) {
    final next = [...widget.relays]..removeAt(index);
    widget.onChanged(next);
  }

  static List<NostrRelayPreference> _mergeRelay(
    List<NostrRelayPreference> relays,
  ) {
    final byUrl = <String, ({bool read, bool write})>{};
    for (final relay in relays) {
      final url = relay.url.trim();
      if (url.isEmpty) continue;
      final current = byUrl[url] ?? (read: false, write: false);
      byUrl[url] = (
        read: current.read || relay.read,
        write: current.write || relay.write,
      );
    }
    return [
      for (final entry in byUrl.entries)
        NostrRelayPreference(
          url: entry.key,
          read: entry.value.read,
          write: entry.value.write,
        ),
    ];
  }
}

class _RelayPreferenceRow extends StatelessWidget {
  final int index;
  final NostrRelayPreference relay;
  final bool isLast;
  final ValueChanged<bool> onReadChanged;
  final ValueChanged<bool> onWriteChanged;
  final VoidCallback onRemove;

  const _RelayPreferenceRow({
    required this.index,
    required this.relay,
    required this.isLast,
    required this.onReadChanged,
    required this.onWriteChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              relay.url,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AnsibleDesign.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _RelayFlagToggle(
            key: Key('nostr_relay_read_$index'),
            label: 'READ',
            value: relay.read,
            onChanged: onReadChanged,
          ),
          const SizedBox(width: 6),
          _RelayFlagToggle(
            key: Key('nostr_relay_write_$index'),
            label: 'WRITE',
            value: relay.write,
            onChanged: onWriteChanged,
          ),
          IconButton(
            key: Key('nostr_remove_relay_$index'),
            tooltip: text.t('removeRelay'),
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _RelayFlagToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RelayFlagToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              value: value,
              onChanged: (next) => onChanged(next ?? false),
            ),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9,
                letterSpacing: 1.2,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRelayRow extends StatelessWidget {
  const _EmptyRelayRow();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 13, 22, 13),
      child: Row(
        children: [
          const Icon(
            Icons.hub_outlined,
            size: 17,
            color: AnsibleDesign.inkFaint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text.t('emptyNostrRelay'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
