enum ReactionType {
  happy,
  sad,
  thumbsUp,
  angry,
}

enum TargetType {
  thread,
  post,
}

class Reaction {
  final String id;
  final String userId;
  final TargetType targetType;
  final String targetId;
  final ReactionType reactionType;
  final DateTime createdAt;

  Reaction({
    required this.id,
    required this.userId,
    required this.targetType,
    required this.targetId,
    required this.reactionType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'targetType': targetType.name,
      'targetId': targetId,
      'reactionType': reactionType.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Reaction.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'] as String? ?? json['userDid'] as String?;
    if (userId == null || userId.isEmpty) {
      throw ArgumentError('Reaction userId is required');
    }

    return Reaction(
      id: json['id'] as String,
      userId: userId,
      targetType: TargetType.values.firstWhere((e) => e.name == json['targetType']),
      targetId: json['targetId'] as String,
      reactionType: ReactionType.values.firstWhere((e) => e.name == json['reactionType']),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
