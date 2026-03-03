import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/api_config.dart';
import '../../models/video.dart';
import '../../models/youtube_video.dart';
import '../../providers/auth_provider.dart';
import '../../providers/video_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/feed_card.dart';
import '../admin/admin_panel_screen.dart';
import '../auth/change_password_screen.dart';
import '../auth/login_screen.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../upload/upload_screen.dart';
import '../video/video_player_screen.dart';
import '../youtube/youtube_player_screen.dart';

// ── Feed item union ────────────────────────────────────────────────────────────
sealed class _FeedItem {}

class _VidMezItem extends _FeedItem {
  final Video video;
  _VidMezItem(this.video);
}

class _YouTubeItem extends _FeedItem {
  final YouTubeVideo video;
  _YouTubeItem(this.video);
}

// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();

  // YouTube trending
  List<YouTubeVideo> _ytVideos = [];
  bool _ytLoading = true;

  // Search state
  bool _searchActive = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoProvider>().loadVideos(refresh: true);
      _loadYouTubeTrending();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      context.read<VideoProvider>().loadVideos();
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<VideoProvider>().loadVideos(refresh: true),
      _loadYouTubeTrending(),
    ]);
  }

  Future<void> _loadYouTubeTrending() async {
    String region = 'US';
    try {
      final locale = Localizations.localeOf(context);
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
        region = locale.countryCode!.toUpperCase();
      }
    } catch (_) {}
    setState(() => _ytLoading = true);
    try {
      final videos = await ApiService.getYouTubeTrending(
        regionCode: region,
        maxResults: 20,
      );
      if (mounted) setState(() { _ytVideos = videos; _ytLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _ytLoading = false);
    }
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  void _activateSearch() {
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      context.read<VideoProvider>().setSearch('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ApiService.getSearchSuggestions(query);
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {}
    });
  }

  void _submitSearch(String query) {
    _debounce?.cancel();
    setState(() => _suggestions = []);
    context.read<VideoProvider>().setSearch(query);
    _searchFocusNode.unfocus();
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) {
    final title = suggestion['title'] as String;
    _searchController.text = title;
    _submitSearch(title);
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() { _suggestions = []; _searchActive = false; });
    context.read<VideoProvider>().setSearch('');
  }

  // ── Share ────────────────────────────────────────────────────────────────────

  Future<void> _shareVideo(BuildContext ctx, Video video) async {
    String url;
    if (kIsWeb) {
      final uri = Uri.base;
      final isDefault = (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      final origin =
          '${uri.scheme}://${uri.host}${isDefault ? '' : ':${uri.port}'}';
      url = '$origin/watch/${video.id}';
    } else {
      url = '${ApiConfig.baseUrl}/watch/${video.id}';
    }
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')));
      }
    } else {
      await Share.share('${video.title}\n$url');
    }
  }

  // ── Feed building ────────────────────────────────────────────────────────────

  /// Interleaves VidMez and YouTube videos 1:1.
  /// During search, shows only VidMez results.
  List<_FeedItem> _buildFeed(List<Video> vidmez, List<YouTubeVideo> yt) {
    if (_searchActive) {
      return vidmez.map((v) => _VidMezItem(v)).toList();
    }
    final result = <_FeedItem>[];
    final len = max(vidmez.length, yt.length);
    for (int i = 0; i < len; i++) {
      if (i < vidmez.length) result.add(_VidMezItem(vidmez[i]));
      if (i < yt.length) result.add(_YouTubeItem(yt[i]));
    }
    return result;
  }

  void _onFeedTap(_FeedItem item) {
    switch (item) {
      case _VidMezItem v:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoId: v.video.id)),
        );
      case _YouTubeItem y:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => YouTubePlayerScreen(video: y.video)),
        );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _fmtViews(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M views';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K views';
    return '$n views';
  }

  Widget _pill(String label, Color bg, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 11),
              const SizedBox(width: 2),
            ],
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _thumbPlaceholder({double iconSize = 40}) => Container(
        color: const Color(0xFF2A2A2A),
        child: Center(
          child: Icon(Icons.play_circle_outline,
              size: iconSize, color: Colors.white24),
        ),
      );

  // ── Hero card (hierarchical — wide screens only) ──────────────────────────

  Widget _buildHeroCard(_FeedItem item) {
    final bool isYT = item is _YouTubeItem;
    final String title;
    final String channel;
    final String? thumbUrl;
    final String duration;
    final String views;

    if (isYT) {
      final v = (item as _YouTubeItem).video;
      title = v.title;
      channel = v.channelTitle;
      thumbUrl = v.thumbnail;
      duration = v.formattedDuration;
      views = v.formattedViews;
    } else {
      final v = (item as _VidMezItem).video;
      title = v.title;
      channel = v.user.email;
      thumbUrl = v.thumbnailCid != null
          ? ApiConfig.thumbnailUrl(v.thumbnailCid!)
          : null;
      duration = v.formattedDuration;
      views = _fmtViews(v.viewCount);
    }

    return GestureDetector(
      onTap: () => _onFeedTap(item),
      child: Container(
        height: 230,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Thumbnail — 58% of width
            Expanded(
              flex: 58,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbUrl != null
                      ? CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _thumbPlaceholder(iconSize: 48),
                          errorWidget: (_, __, ___) =>
                              _thumbPlaceholder(iconSize: 48),
                        )
                      : _thumbPlaceholder(iconSize: 48),
                  // Duration badge
                  Positioned(
                      right: 8,
                      bottom: 8,
                      child: _pill(duration, Colors.black87)),
                  // Source badge
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _pill(
                      isYT ? 'YouTube Trending' : 'VidMez',
                      isYT ? Colors.red : const Color(0xFF1E88E5),
                      icon: isYT
                          ? Icons.play_arrow
                          : Icons.play_circle_filled,
                    ),
                  ),
                ],
              ),
            ),

            // Info — 42% of width
            Expanded(
              flex: 42,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      channel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$views · $duration',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
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

  // ── Grid card ────────────────────────────────────────────────────────────────

  Widget _buildGridCard(_FeedItem item) {
    switch (item) {
      case _VidMezItem v:
        return FeedCard.vidmez(video: v.video, onTap: () => _onFeedTap(item));
      case _YouTubeItem y:
        return FeedCard.youtube(video: y.video, onTap: () => _onFeedTap(item));
    }
  }

  // ── AppBar ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final videoProvider = context.watch<VideoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: _searchActive
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search videos...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
              )
            : const Row(
                children: [
                  Icon(Icons.play_circle_filled, color: Color(0xFF1E88E5)),
                  SizedBox(width: 8),
                  Text('VidMez',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
        actions: [
          if (_searchActive)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel search',
              onPressed: _clearSearch,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search',
              onPressed: _activateSearch,
            ),
            if (auth.isAuthenticated) ...[
              if (auth.isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings,
                      color: Color(0xFFFFB300)),
                  tooltip: 'Admin Panel',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminPanelScreen()),
                  ).then((_) => _refresh()),
                ),
              IconButton(
                icon: const Icon(Icons.upload_rounded),
                tooltip: 'Upload video',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UploadScreen()),
                ).then((_) => _refresh()),
              ),
              PopupMenuButton<String>(
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1E88E5),
                  child: Text(
                    auth.user!.email[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                onSelected: (value) {
                  if (value == 'logout') {
                    auth.logout();
                  } else if (value == 'change_password') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen()));
                  } else if (value == 'bookmarks') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BookmarksScreen()));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(auth.user!.email,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'bookmarks',
                    child: Row(children: [
                      Icon(Icons.bookmark_border, size: 18),
                      SizedBox(width: 8),
                      Text('Bookmarks'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'change_password',
                    child: Row(children: [
                      Icon(Icons.lock_reset, size: 18),
                      SizedBox(width: 8),
                      Text('Change Password'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 8),
                      Text('Log Out'),
                    ]),
                  ),
                ],
              ),
            ] else
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Log In'),
              ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: _buildBody(videoProvider),
          ),
          if (_searchActive && _suggestions.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                color: const Color(0xFF2A2A2A),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions
                      .map((s) => ListTile(
                            leading:
                                const Icon(Icons.search, color: Colors.grey),
                            title: Text(s['title'] as String,
                                style:
                                    const TextStyle(color: Colors.white)),
                            onTap: () => _selectSuggestion(s),
                          ))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────────────

  Widget _buildBody(VideoProvider videoProvider) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Show spinner only when truly nothing has loaded yet
    final nothingLoaded = videoProvider.videos.isEmpty && _ytVideos.isEmpty;
    if (nothingLoaded && videoProvider.loading && _ytLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Error state (no content at all)
    if (videoProvider.error != null && nothingLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(videoProvider.error!,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    final feed = _buildFeed(videoProvider.videos, _ytVideos);

    // Empty state
    if (feed.isEmpty && !videoProvider.loading && !_ytLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined,
                size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No videos yet. Be the first to upload!',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _refresh, child: const Text('Refresh')),
          ],
        ),
      );
    }

    // ── Responsive grid dimensions ───────────────────────────────────────────
    const double hPad = 12;
    const double gap = 10;

    // Web: 2–5 columns at ~300 px each; mobile: always 2 columns
    final bool isWide = screenWidth > 700;
    final int cols =
        isWide ? (screenWidth / 300).floor().clamp(2, 5) : 2;

    // Card width → thumbnail height (16:9) + fixed info strip = total height
    final double cardWidth =
        (screenWidth - 2 * hPad - (cols - 1) * gap) / cols;
    final double mainAxisExtent = cardWidth * 9 / 16 + 78;

    // ── Hierarchical hero (wide screens) ────────────────────────────────────
    // First feed item shown as a full-width hero; rest fill the grid.
    final _FeedItem? heroItem =
        (isWide && feed.isNotEmpty) ? feed.first : null;
    final List<_FeedItem> gridFeed =
        heroItem != null ? feed.skip(1).toList() : feed;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Hero card — hierarchical, wide screens only
        if (heroItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
              child: _buildHeroCard(heroItem),
            ),
          ),

        // Modular grid — all screens
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              hPad, heroItem == null ? 12 : 4, hPad, 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: cardWidth / mainAxisExtent,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, idx) {
                if (idx >= gridFeed.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return _buildGridCard(gridFeed[idx]);
              },
              childCount:
                  gridFeed.length + (videoProvider.hasMore ? 1 : 0),
            ),
          ),
        ),
      ],
    );
  }
}
