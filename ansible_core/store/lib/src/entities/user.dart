class User {
  final String userId;
  final String username;
  final String passwordHash;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.userId,
    required this.username,
    required this.passwordHash,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['userId'] as String,
      username: json['username'] as String,
      passwordHash: json['passwordHash'] as String, // Usually not in JSON, but for internal use maybe
      displayName: json['displayName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
