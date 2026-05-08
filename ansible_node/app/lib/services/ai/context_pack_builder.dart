import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

typedef ContextPackIdFactory = String Function();
typedef ContextPackClock = DateTime Function();

class ContextPackBuilder {
  final ContextPackIdFactory _idFactory;
  final ContextPackClock _clock;

  const ContextPackBuilder({
    required ContextPackIdFactory idFactory,
    ContextPackClock? clock,
  }) : _idFactory = idFactory,
       _clock = clock ?? DateTime.now;

  ContextPack forTransformation({
    required ContextPackPurpose purpose,
    required String createdByDid,
    required List<ContentItem> sources,
  }) {
    return _build(
      purpose: purpose,
      createdByDid: createdByDid,
      sources: sources,
    );
  }

  ContextPack forSummary({
    required ContextPackPurpose purpose,
    required String createdByDid,
    required List<ContentItem> sources,
  }) {
    return _build(
      purpose: purpose,
      createdByDid: createdByDid,
      sources: sources,
    );
  }

  ContextPack _build({
    required ContextPackPurpose purpose,
    required String createdByDid,
    required List<ContentItem> sources,
  }) {
    final privacyLevel = _privacyLevelFor(sources);
    return ContextPack(
      id: _idFactory(),
      purpose: purpose,
      sourceRefsJson: jsonEncode(sources.map((item) => item.id).toList()),
      snapshotJson: jsonEncode({
        'sources': sources
            .map(
              (item) => {
                'id': item.id,
                'mode': item.mode.name,
                'title': item.title,
                'body': item.body,
                'visibility': item.visibility.name,
                'localOnly': item.localOnly,
              },
            )
            .toList(),
      }),
      privacyLevel: privacyLevel,
      allowedRemote: privacyLevel == ContextPrivacyLevel.publicOnly,
      createdByDid: createdByDid,
      createdAt: _clock().toUtc(),
    );
  }

  ContextPrivacyLevel _privacyLevelFor(List<ContentItem> sources) {
    if (sources.any((item) => item.visibility == ContentVisibility.private)) {
      return ContextPrivacyLevel.containsPrivate;
    }
    return ContextPrivacyLevel.publicOnly;
  }
}
