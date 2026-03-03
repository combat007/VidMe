class YouTubeVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String channelId;
  final String? thumbnail;
  final String publishedAt;
  final String viewCount;
  final String likeCount;
  final String duration;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.channelId,
    this.thumbnail,
    required this.publishedAt,
    required this.viewCount,
    required this.likeCount,
    required this.duration,
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) => YouTubeVideo(
        id: json['id'] as String,
        title: json['title'] as String,
        channelTitle: json['channelTitle'] as String,
        channelId: json['channelId'] as String? ?? '',
        thumbnail: json['thumbnail'] as String?,
        publishedAt: json['publishedAt'] as String? ?? '',
        viewCount: json['viewCount'] as String? ?? '0',
        likeCount: json['likeCount'] as String? ?? '0',
        duration: json['duration'] as String? ?? 'PT0S',
      );

  String get formattedDuration => _parseDuration(duration);

  String get formattedViews {
    final n = int.tryParse(viewCount) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M views';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K views';
    return '$n views';
  }

  static String _parseDuration(String iso) {
    final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
    if (m == null) return '0:00';
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final s = int.tryParse(m.group(3) ?? '') ?? 0;
    if (h > 0) {
      return '$h:${min.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$min:${s.toString().padLeft(2, '0')}';
  }
}
