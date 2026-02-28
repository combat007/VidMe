class VideoUser {
  final String id;
  final String email;

  const VideoUser({required this.id, required this.email});

  factory VideoUser.fromJson(Map<String, dynamic> json) =>
      VideoUser(id: json['id'] as String, email: json['email'] as String);
}

class VideoCount {
  final int likes;
  final int comments;

  const VideoCount({required this.likes, required this.comments});

  factory VideoCount.fromJson(Map<String, dynamic> json) => VideoCount(
        likes: json['likes'] as int? ?? 0,
        comments: json['comments'] as int? ?? 0,
      );
}

class Video {
  final String id;
  final String userId;
  final VideoUser user;
  final String title;
  final String? description;
  final String ipfsCid;
  final String? thumbnailCid;
  final String gatewayUrl;
  final String? thumbnailUrl;
  final int duration;
  final bool is18Plus;
  final bool blocked;
  final bool likesEnabled;
  final bool commentsEnabled;
  final String status;
  final int viewCount;
  final DateTime createdAt;
  final VideoCount count;

  const Video({
    required this.id,
    required this.userId,
    required this.user,
    required this.title,
    this.description,
    required this.ipfsCid,
    this.thumbnailCid,
    required this.gatewayUrl,
    this.thumbnailUrl,
    required this.duration,
    required this.is18Plus,
    this.blocked = false,
    required this.likesEnabled,
    required this.commentsEnabled,
    required this.status,
    required this.viewCount,
    required this.createdAt,
    required this.count,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      id: json['id'] as String,
      userId: json['userId'] as String,
      user: VideoUser.fromJson(json['user'] as Map<String, dynamic>),
      title: json['title'] as String,
      description: json['description'] as String?,
      ipfsCid: json['ipfsCid'] as String,
      thumbnailCid: json['thumbnailCid'] as String?,
      gatewayUrl: json['gatewayUrl'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      duration: json['duration'] as int,
      is18Plus: json['is18Plus'] as bool? ?? false,
      blocked: json['blocked'] as bool? ?? false,
      likesEnabled: json['likesEnabled'] as bool? ?? true,
      commentsEnabled: json['commentsEnabled'] as bool? ?? true,
      status: json['status'] as String? ?? 'PUBLISHED',
      viewCount: json['viewCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      count: json['_count'] != null
          ? VideoCount.fromJson(json['_count'] as Map<String, dynamic>)
          : const VideoCount(likes: 0, comments: 0),
    );
  }

  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
