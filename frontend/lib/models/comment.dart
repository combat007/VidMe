class CommentUser {
  final String id;
  final String email;

  const CommentUser({required this.id, required this.email});

  factory CommentUser.fromJson(Map<String, dynamic> json) =>
      CommentUser(id: json['id'] as String, email: json['email'] as String);
}

class Comment {
  final String id;
  final String userId;
  final String videoId;
  final String content;
  final CommentUser user;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.userId,
    required this.videoId,
    required this.content,
    required this.user,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      userId: json['userId'] as String,
      videoId: json['videoId'] as String,
      content: json['content'] as String,
      user: CommentUser.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
