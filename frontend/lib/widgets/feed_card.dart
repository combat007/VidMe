import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../models/video.dart';
import '../models/youtube_video.dart';

/// Unified grid card for both VidMez and YouTube videos.
class FeedCard extends StatelessWidget {
  final Video? _vidmezVideo;
  final YouTubeVideo? _ytVideo;
  final VoidCallback onTap;

  const FeedCard.vidmez({
    super.key,
    required Video video,
    required this.onTap,
  })  : _vidmezVideo = video,
        _ytVideo = null;

  const FeedCard.youtube({
    super.key,
    required YouTubeVideo video,
    required this.onTap,
  })  : _ytVideo = video,
        _vidmezVideo = null;

  bool get _isYT => _ytVideo != null;

  static String _fmtViews(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M views';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K views';
    return '$n views';
  }

  @override
  Widget build(BuildContext context) {
    final title = _isYT ? _ytVideo!.title : _vidmezVideo!.title;
    final channel =
        _isYT ? _ytVideo!.channelTitle : _vidmezVideo!.user.email;
    final duration = _isYT
        ? _ytVideo!.formattedDuration
        : _vidmezVideo!.formattedDuration;
    final views = _isYT
        ? _ytVideo!.formattedViews
        : _fmtViews(_vidmezVideo!.viewCount);
    final thumbUrl = _isYT
        ? _ytVideo!.thumbnail
        : (_vidmezVideo!.thumbnailCid != null
            ? ApiConfig.thumbnailUrl(_vidmezVideo!.thumbnailCid!)
            : null);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ────────────────────────────────────────────────────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbUrl != null
                      ? CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _placeholder(),
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                  // Duration badge
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _pill(duration, Colors.black87),
                  ),
                  // Source badge
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _isYT
                        ? _pill('YT', Colors.red, icon: Icons.play_arrow)
                        : _pill('V', const Color(0xFF1E88E5),
                            icon: Icons.play_circle_filled),
                  ),
                ],
              ),
            ),

            // ── Info ─────────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 11.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          views,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF2A2A2A),
        child: const Center(
          child: Icon(Icons.play_circle_outline, size: 36, color: Colors.white24),
        ),
      );

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 10),
              const SizedBox(width: 2),
            ],
            Text(
              text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}
