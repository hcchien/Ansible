const _activityStreamsContext = 'https://www.w3.org/ns/activitystreams';
const _trisAuraFollowContext = 'https://trisaura.io/ns/follow';

class FollowActivity {
  final String id;
  final String actor;
  final String object;
  final DateTime? published;
  final bool isBoardFollow;
  final String? boardId;

  const FollowActivity({
    required this.id,
    required this.actor,
    required this.object,
    required this.published,
    this.isBoardFollow = false,
    this.boardId,
  });

  factory FollowActivity.user({
    required String id,
    required String actor,
    required String object,
    required DateTime published,
  }) {
    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
    );
  }

  factory FollowActivity.board({
    required String id,
    required String actor,
    required String object,
    required String boardId,
    required DateTime published,
  }) {
    if (boardId.isEmpty) {
      throw const FormatException('Board follow boardId is required.');
    }

    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
      isBoardFollow: true,
      boardId: boardId,
    );
  }

  factory FollowActivity.fromJson(Map<String, dynamic> json) {
    _expectType(json, 'Follow', label: 'Follow');
    final id = _requiredString(json, 'id', 'Follow id is required.');
    final actor = _requiredString(json, 'actor', 'Follow actor is required.');
    final object = _requiredString(
      json,
      'object',
      'Follow object is required.',
    );
    final published = _optionalDateTime(json, 'published');

    final isBoardFollow = json['trisAura:targetType'] == 'board';
    final boardId = json['trisAura:boardId'];
    if (isBoardFollow && (boardId is! String || boardId.isEmpty)) {
      throw const FormatException('Board follow boardId is required.');
    }

    return FollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
      isBoardFollow: isBoardFollow,
      boardId: boardId as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      '@context': isBoardFollow
          ? [_activityStreamsContext, _trisAuraFollowContext]
          : _activityStreamsContext,
      'id': id,
      'type': 'Follow',
      'actor': actor,
      'object': object,
      'to': [object],
    };

    if (published != null) {
      json['published'] = _formatDate(published!);
    }

    if (isBoardFollow) {
      json['trisAura:targetType'] = 'board';
      json['trisAura:boardId'] = boardId;
    }

    return json;
  }
}

enum FollowResponseType {
  accept('Accept'),
  reject('Reject');

  final String activityType;

  const FollowResponseType(this.activityType);

  static FollowResponseType parse(String value) {
    return switch (value) {
      'Accept' => FollowResponseType.accept,
      'Reject' => FollowResponseType.reject,
      _ => throw const FormatException(
        'Follow response type must be Accept or Reject.',
      ),
    };
  }
}

class FollowResponseActivity {
  final String id;
  final FollowResponseType type;
  final String actor;
  final FollowActivity object;
  final DateTime published;

  const FollowResponseActivity({
    required this.id,
    required this.type,
    required this.actor,
    required this.object,
    required this.published,
  });

  factory FollowResponseActivity.accept({
    required String id,
    required String actor,
    required FollowActivity object,
    required DateTime published,
  }) {
    return FollowResponseActivity(
      id: id,
      type: FollowResponseType.accept,
      actor: actor,
      object: object,
      published: published,
    );
  }

  factory FollowResponseActivity.reject({
    required String id,
    required String actor,
    required FollowActivity object,
    required DateTime published,
  }) {
    return FollowResponseActivity(
      id: id,
      type: FollowResponseType.reject,
      actor: actor,
      object: object,
      published: published,
    );
  }

  factory FollowResponseActivity.fromJson(Map<String, dynamic> json) {
    final typeValue = _requiredString(
      json,
      'type',
      'Follow response type is required.',
    );
    final type = FollowResponseType.parse(typeValue);
    final id = _requiredString(json, 'id', 'Follow response id is required.');
    final actor = _requiredString(
      json,
      'actor',
      'Follow response actor is required.',
    );
    final object = _requiredFollowObject(
      json,
      'Follow response object is required.',
    );
    final published = _requiredDateTime(
      json,
      'published',
      'Follow response published timestamp is required.',
    );

    return FollowResponseActivity(
      id: id,
      type: type,
      actor: actor,
      object: object,
      published: published,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '@context': _activityStreamsContext,
      'id': id,
      'type': type.activityType,
      'actor': actor,
      'object': object.toJson(),
      'to': [object.actor],
      'published': _formatDate(published),
    };
  }
}

class UndoFollowActivity {
  final String id;
  final String actor;
  final FollowActivity object;
  final DateTime published;

  const UndoFollowActivity({
    required this.id,
    required this.actor,
    required this.object,
    required this.published,
  });

  factory UndoFollowActivity.fromJson(Map<String, dynamic> json) {
    _expectType(json, 'Undo', label: 'Undo');
    final id = _requiredString(json, 'id', 'Undo id is required.');
    final actor = _requiredString(json, 'actor', 'Undo actor is required.');
    final object = _requiredFollowObject(json, 'Undo object is required.');
    final published = _requiredDateTime(
      json,
      'published',
      'Undo published timestamp is required.',
    );

    return UndoFollowActivity(
      id: id,
      actor: actor,
      object: object,
      published: published,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '@context': _activityStreamsContext,
      'id': id,
      'type': 'Undo',
      'actor': actor,
      'object': object.toJson(),
      'to': [object.object],
      'published': _formatDate(published),
    };
  }
}

void _expectType(
  Map<String, dynamic> json,
  String expected, {
  required String label,
}) {
  if (json['type'] != expected) {
    throw FormatException('Activity type must be $label.');
  }
}

String _requiredString(Map<String, dynamic> json, String key, String message) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(message);
  }
  return value;
}

DateTime _requiredDateTime(
  Map<String, dynamic> json,
  String key,
  String message,
) {
  final value = _requiredString(json, key, message);
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException(message);
  }
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be an ISO-8601 string.');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('$key must be an ISO-8601 string.');
  }
}

FollowActivity _requiredFollowObject(
  Map<String, dynamic> json,
  String message,
) {
  final value = json['object'];
  if (value is! Map<String, dynamic>) {
    throw FormatException(message);
  }
  return FollowActivity.fromJson(value);
}

String _formatDate(DateTime value) {
  return value.toUtc().toIso8601String();
}
