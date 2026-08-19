import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/fediverse_preferences_controller.dart';
import '../theme/ansible_design.dart';

Future<ContentVisibility?> showContentVisibilitySheet({
  required BuildContext context,
  required ContentVisibility current,
  required String subjectLabel,
  String? authorDid,
}) {
  return showContentDistributionSheet(
    context: context,
    current: ContentDistributionChoice.forVisibility(current),
    subjectLabel: subjectLabel,
    authorDid: authorDid,
  ).then((choice) => choice?.visibility);
}

Future<ContentDistributionChoice?> showContentDistributionSheet({
  required BuildContext context,
  required ContentDistributionChoice current,
  required String subjectLabel,
  String? authorDid,
  FediversePreferencesStore preferencesStore =
      const SharedPreferencesFediversePreferencesStore(),
}) {
  // ActivityPub is an explicit, high-trust distribution rail.  An active Elix
  // Relay is only a sync endpoint; it is never consent to create an external
  // actor or distribute content there.  The Relay remains authoritative, but
  // this local consent check prevents an unverified account from queuing a
  // request the Relay must reject.
  var activityPubAvailable = false;
  var sheetClosed = false;
  var distributionChanged = false;
  StateSetter? refreshSheet;
  var picked = current.visibility;
  var distributionPreference = _withoutUnavailableActivityPub(
    current.distributionPreference,
    activityPubAvailable: activityPubAvailable,
  );

  void normalizeDistribution() {
    if (picked == ContentVisibility.private) {
      distributionPreference = DistributionPreference.localOnly;
    }
  }

  final sheet = showModalBottomSheet<ContentDistributionChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AnsibleDesign.ink.withValues(alpha: 0.20),
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          refreshSheet = setSheetState;
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
              distributionChanged = true;
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
              child: Material(
                type: MaterialType.transparency,
                child: Theme(
                  // This sheet deliberately uses a paper surface, including
                  // when the app follows a dark system theme. Keep controls
                  // on the same palette so their labels and selected states
                  // remain visible.
                  data: Theme.of(
                    context,
                  ).copyWith(switchTheme: AnsibleDesign.paperSwitchTheme()),
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
                            activityPubAvailable: activityPubAvailable,
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
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AnsibleDesign.ink,
                                  side: const BorderSide(
                                    color: AnsibleDesign.inkMuted,
                                  ),
                                ),
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                child: Text(
                                  context.uiCopy(zh: '取消', en: 'Cancel'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AnsibleDesign.accent,
                                  foregroundColor: AnsibleDesign.ink,
                                ),
                                onPressed: () => Navigator.of(sheetContext).pop(
                                  ContentDistributionChoice(
                                    visibility: picked,
                                    distributionPreference:
                                        distributionPreference,
                                  ),
                                ),
                                child: Text(
                                  context.uiCopy(zh: '確認', en: 'Confirm'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  if (authorDid != null) {
    unawaited(
      preferencesStore
          .load(authorDid)
          .then((preferences) {
            if (sheetClosed) return;
            void applyAvailability() {
              activityPubAvailable = preferences.enabled;
              distributionPreference =
                  preferences.enabled && !distributionChanged
                  ? current.distributionPreference
                  : _withoutUnavailableActivityPub(
                      distributionPreference,
                      activityPubAvailable: preferences.enabled,
                    );
            }

            final update = refreshSheet;
            if (update == null) {
              applyAvailability();
            } else {
              update(applyAvailability);
            }
          })
          .catchError((Object _) {
            // A missing or unreadable local preference is equivalent to no
            // ActivityPub consent. The visibility controls remain usable.
          }),
    );
  }

  return sheet.whenComplete(() => sheetClosed = true);
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
          : DistributionPreference.localOnly,
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

DistributionPreference _withoutUnavailableActivityPub(
  DistributionPreference preference, {
  required bool activityPubAvailable,
}) {
  if (activityPubAvailable) return preference;
  return switch (preference) {
    DistributionPreference.activityPub => DistributionPreference.localOnly,
    DistributionPreference.nostrAndActivityPub => DistributionPreference.nostr,
    _ => preference,
  };
}

({String label, Color dot}) contentVisibilityMeta(
  BuildContext context,
  ContentVisibility visibility,
) {
  return switch (visibility) {
    ContentVisibility.private => (
      label: context.uiCopy(zh: '私人', en: 'private'),
      dot: AnsibleDesign.inkMuted,
    ),
    ContentVisibility.unlisted => (
      label: context.uiCopy(zh: '未列出', en: 'unlisted'),
      dot: AnsibleDesign.spore,
    ),
    ContentVisibility.public => (
      label: context.uiCopy(zh: '公開', en: 'public'),
      dot: AnsibleDesign.accent,
    ),
  };
}

class _DistributionSheetMainContent extends StatelessWidget {
  final String subjectLabel;
  final ContentVisibility picked;
  final bool federationEnabled;
  final bool nostrEnabled;
  final bool activityPubEnabled;
  final bool activityPubAvailable;
  final ValueChanged<ContentVisibility> onPickVisibility;
  final ValueChanged<bool> onNostrChanged;
  final ValueChanged<bool> onActivityPubChanged;

  const _DistributionSheetMainContent({
    required this.subjectLabel,
    required this.picked,
    required this.federationEnabled,
    required this.nostrEnabled,
    required this.activityPubEnabled,
    required this.activityPubAvailable,
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
              Text(
                context.uiCopy(zh: '誰能看見 · VISIBILITY', en: 'VISIBILITY'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.uiCopy(
                  zh: '$subjectLabel 給誰看？',
                  en: 'Who can see $subjectLabel?',
                ),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.uiCopy(
                  zh: '之後也可以改。預設留在你這裡。',
                  en: 'You can change this later. The default stays local.',
                ),
                style: const TextStyle(
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
          activityPubAvailable: activityPubAvailable,
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
  final bool activityPubAvailable;
  final ValueChanged<bool> onNostrChanged;
  final ValueChanged<bool> onActivityPubChanged;

  const _DistributionSettings({
    required this.enabled,
    required this.nostrEnabled,
    required this.activityPubEnabled,
    required this.activityPubAvailable,
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
          Text(
            context.uiCopy(zh: '散布', en: 'DISTRIBUTION'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              letterSpacing: 1.4,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          _DistributionToggle(
            key: const Key('distribution_nostr_toggle'),
            label: context.uiCopy(zh: 'Nostr 中繼站', en: 'Nostr relays'),
            value: enabled && nostrEnabled,
            enabled: enabled && (activityPubEnabled || !nostrEnabled),
            onChanged: onNostrChanged,
          ),
          _DistributionToggle(
            key: const Key('distribution_activitypub_toggle'),
            label: context.uiCopy(
              zh: 'ActivityPub 中繼站',
              en: 'ActivityPub relay',
            ),
            value: enabled && activityPubAvailable && activityPubEnabled,
            enabled:
                enabled &&
                activityPubAvailable &&
                (nostrEnabled || !activityPubEnabled),
            onChanged: onActivityPubChanged,
          ),
          if (!activityPubAvailable) ...[
            const SizedBox(height: 4),
            Text(
              context.uiCopy(
                zh: '需先在設定完成真人驗證並啟用 Fediverse 發布。',
                en: 'Verify your humanity and enable Fediverse publishing in Settings first.',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 11,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            summary,
            key: const Key('distribution_summary'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11,
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
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 8),
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
                        context.uiCopy(zh: option.zh, en: option.enLabel),
                        style: const TextStyle(
                          fontSize: 18,
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
                            fontSize: 10.5,
                            letterSpacing: 1.5,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.uiCopy(
                      zh: option.description,
                      en: option.descriptionEn,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
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
                        width: 8,
                        height: 8,
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
    required this.enLabel,
    required this.description,
    required this.descriptionEn,
    required this.dot,
  });

  final ContentVisibility visibility;
  final String zh;
  final String en;
  final String enLabel;
  final String description;
  final String descriptionEn;
  final Color dot;
}

const _visibilityOptions = [
  _VisibilityOption(
    visibility: ContentVisibility.private,
    zh: '留在本地',
    en: 'private',
    enLabel: 'Private',
    description: '只有你看得見。連同步到別台也只有你的裝置。',
    descriptionEn: 'Only you can see it. Even sync stays on your devices.',
    dot: AnsibleDesign.inkMuted,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.unlisted,
    zh: '不列出',
    en: 'unlisted',
    description: '可以同步與分享連結，但不主動放進公開列表或索引。',
    enLabel: 'Unlisted',
    descriptionEn:
        'Can sync and be shared by link, but is not listed or indexed.',
    dot: AnsibleDesign.spore,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.public,
    zh: '公開',
    en: 'public',
    description: '任何人都能讀。會出現在公開討論串裡。',
    enLabel: 'Public',
    descriptionEn: 'Anyone can read it. It can appear in public discussions.',
    dot: AnsibleDesign.accent,
  ),
];
