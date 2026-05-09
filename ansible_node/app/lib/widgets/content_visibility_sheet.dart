import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

Future<ContentVisibility?> showContentVisibilitySheet({
  required BuildContext context,
  required ContentVisibility current,
  required String subjectLabel,
}) {
  return showContentDistributionSheet(
    context: context,
    current: ContentDistributionChoice.forVisibility(current),
    subjectLabel: subjectLabel,
  ).then((choice) => choice?.visibility);
}

Future<ContentDistributionChoice?> showContentDistributionSheet({
  required BuildContext context,
  required ContentDistributionChoice current,
  required String subjectLabel,
}) {
  var picked = current.visibility;
  var distributionPreference = current.distributionPreference;

  void normalizeDistribution() {
    if (picked == ContentVisibility.private) {
      distributionPreference = DistributionPreference.localOnly;
    } else if (distributionPreference == DistributionPreference.localOnly) {
      distributionPreference = DistributionPreference.nostrAndActivityPub;
    }
  }

  return showModalBottomSheet<ContentDistributionChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AnsibleDesign.ink.withValues(alpha: 0.20),
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final nostrEnabled =
              distributionPreference == DistributionPreference.nostr ||
              distributionPreference ==
                  DistributionPreference.nostrAndActivityPub;
          final activityPubEnabled =
              distributionPreference == DistributionPreference.activityPub ||
              distributionPreference ==
                  DistributionPreference.nostrAndActivityPub;
          final federationEnabled = picked != ContentVisibility.private;

          void setDistribution({bool? nostr, bool? activityPub}) {
            if (!federationEnabled) return;
            final nextNostr = nostr ?? nostrEnabled;
            final nextActivityPub = activityPub ?? activityPubEnabled;
            if (!nextNostr && !nextActivityPub) return;
            setSheetState(() {
              distributionPreference = ContentDistributionChoice.preferenceFor(
                nostr: nextNostr,
                activityPub: nextActivityPub,
              );
            });
          }

          return SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: AnsibleDesign.paper,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AnsibleDesign.ink.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: _DistributionSheetMainContent(
                        subjectLabel: subjectLabel,
                        picked: picked,
                        federationEnabled: federationEnabled,
                        nostrEnabled: nostrEnabled,
                        activityPubEnabled: activityPubEnabled,
                        onPickVisibility: (visibility) => setSheetState(() {
                          picked = visibility;
                          normalizeDistribution();
                        }),
                        onNostrChanged: (value) =>
                            setDistribution(nostr: value),
                        onActivityPubChanged: (value) =>
                            setDistribution(activityPub: value),
                      ),
                    ),
                  ),
                  const Divider(height: 0.5, color: AnsibleDesign.rule),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () => Navigator.of(sheetContext).pop(
                              ContentDistributionChoice(
                                visibility: picked,
                                distributionPreference: distributionPreference,
                              ),
                            ),
                            child: const Text('確認'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class ContentDistributionChoice {
  final ContentVisibility visibility;
  final DistributionPreference distributionPreference;

  const ContentDistributionChoice({
    required this.visibility,
    required this.distributionPreference,
  });

  factory ContentDistributionChoice.forVisibility(
    ContentVisibility visibility,
  ) {
    return ContentDistributionChoice(
      visibility: visibility,
      distributionPreference: visibility == ContentVisibility.private
          ? DistributionPreference.localOnly
          : DistributionPreference.nostrAndActivityPub,
    );
  }

  static DistributionPreference preferenceFor({
    required bool nostr,
    required bool activityPub,
  }) {
    if (nostr && activityPub) return DistributionPreference.nostrAndActivityPub;
    if (nostr) return DistributionPreference.nostr;
    if (activityPub) return DistributionPreference.activityPub;
    return DistributionPreference.localOnly;
  }
}

({String label, Color dot}) contentVisibilityMeta(
  ContentVisibility visibility,
) {
  return switch (visibility) {
    ContentVisibility.private => (
      label: 'private',
      dot: AnsibleDesign.inkMuted,
    ),
    ContentVisibility.unlisted => (label: 'unlisted', dot: AnsibleDesign.spore),
    ContentVisibility.public => (label: 'public', dot: AnsibleDesign.accent),
  };
}

class _DistributionSheetMainContent extends StatelessWidget {
  final String subjectLabel;
  final ContentVisibility picked;
  final bool federationEnabled;
  final bool nostrEnabled;
  final bool activityPubEnabled;
  final ValueChanged<ContentVisibility> onPickVisibility;
  final ValueChanged<bool> onNostrChanged;
  final ValueChanged<bool> onActivityPubChanged;

  const _DistributionSheetMainContent({
    required this.subjectLabel,
    required this.picked,
    required this.federationEnabled,
    required this.nostrEnabled,
    required this.activityPubEnabled,
    required this.onPickVisibility,
    required this.onNostrChanged,
    required this.onActivityPubChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: AnsibleDesign.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '誰能看見 · VISIBILITY',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 9.5,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$subjectLabel 給誰看？',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '之後也可以改。預設留在你這裡。',
                style: TextStyle(
                  fontSize: 12,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 0.5, color: AnsibleDesign.rule),
        for (final option in _visibilityOptions)
          _VisibilityOptionRow(
            option: option,
            selected: picked == option.visibility,
            onTap: () => onPickVisibility(option.visibility),
          ),
        const Divider(height: 0.5, color: AnsibleDesign.rule),
        _DistributionSettings(
          enabled: federationEnabled,
          nostrEnabled: nostrEnabled,
          activityPubEnabled: activityPubEnabled,
          onNostrChanged: onNostrChanged,
          onActivityPubChanged: onActivityPubChanged,
        ),
      ],
    );
  }
}

class _DistributionSettings extends StatelessWidget {
  final bool enabled;
  final bool nostrEnabled;
  final bool activityPubEnabled;
  final ValueChanged<bool> onNostrChanged;
  final ValueChanged<bool> onActivityPubChanged;

  const _DistributionSettings({
    required this.enabled,
    required this.nostrEnabled,
    required this.activityPubEnabled,
    required this.onNostrChanged,
    required this.onActivityPubChanged,
  });

  @override
  Widget build(BuildContext context) {
    final summary = !enabled
        ? 'local only'
        : switch ((nostrEnabled, activityPubEnabled)) {
            (true, true) => 'Nostr + ActivityPub',
            (true, false) => 'Nostr',
            (false, true) => 'ActivityPub',
            _ => 'local only',
          };

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DISTRIBUTION',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              letterSpacing: 1.4,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          _DistributionToggle(
            key: const Key('distribution_nostr_toggle'),
            label: 'Nostr relays',
            value: enabled && nostrEnabled,
            enabled: enabled && (activityPubEnabled || !nostrEnabled),
            onChanged: onNostrChanged,
          ),
          _DistributionToggle(
            key: const Key('distribution_activitypub_toggle'),
            label: 'ActivityPub relay',
            value: enabled && activityPubEnabled,
            enabled: enabled && (nostrEnabled || !activityPubEnabled),
            onChanged: onActivityPubChanged,
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            key: const Key('distribution_summary'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              color: AnsibleDesign.inkMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionToggle extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _DistributionToggle({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: enabled ? AnsibleDesign.ink : AnsibleDesign.inkFaint,
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _VisibilityOptionRow extends StatelessWidget {
  const _VisibilityOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _VisibilityOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AnsibleDesign.paperElev : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: option.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        option.zh,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          option.en,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9,
                            letterSpacing: 1.5,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: selected ? AnsibleDesign.ink : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AnsibleDesign.ink : AnsibleDesign.rule,
                  width: 0.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AnsibleDesign.paper,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption {
  const _VisibilityOption({
    required this.visibility,
    required this.zh,
    required this.en,
    required this.description,
    required this.dot,
  });

  final ContentVisibility visibility;
  final String zh;
  final String en;
  final String description;
  final Color dot;
}

const _visibilityOptions = [
  _VisibilityOption(
    visibility: ContentVisibility.private,
    zh: '留在本地',
    en: 'private',
    description: '只有你看得見。連同步到別台也只有你的裝置。',
    dot: AnsibleDesign.inkMuted,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.unlisted,
    zh: '送進讀書會',
    en: 'unlisted',
    description: '圈內 4 人都能讀。可以再加，但離開的人讀不到新的。',
    dot: AnsibleDesign.spore,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.public,
    zh: '公開',
    en: 'public',
    description: '任何人都能讀。會出現在公開討論串裡。',
    dot: AnsibleDesign.accent,
  ),
];
