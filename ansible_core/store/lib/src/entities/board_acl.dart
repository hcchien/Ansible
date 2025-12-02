class BoardAcl {
  final String boardId;
  final String userId;
  final bool canRead;
  final bool canWrite;
  final bool isAdmin;

  BoardAcl({
    required this.boardId,
    required this.userId,
    this.canRead = true,
    this.canWrite = true,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'boardId': boardId,
      'userId': userId,
      'canRead': canRead,
      'canWrite': canWrite,
      'isAdmin': isAdmin,
    };
  }

  factory BoardAcl.fromJson(Map<String, dynamic> json) {
    return BoardAcl(
      boardId: json['boardId'] as String,
      userId: json['userId'] as String,
      canRead: json['canRead'] as bool? ?? true,
      canWrite: json['canWrite'] as bool? ?? true,
      isAdmin: json['isAdmin'] as bool? ?? false,
    );
  }
}
