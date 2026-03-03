import 'dart:async';
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
import '../../widgets/video_card.dart';
import '../../widgets/youtube_video_card.dart';
import '../bookmarks/bookmarks_screen.dart';
import '../upload/upload_screen.dart';
import '../video/video_player_screen.dart';
import '../youtube/youtube_player_screen.dart';
import '../admin/admin_panel_screen.dart';
import '../auth/change_password_screen.dart';
import '../auth/login_screen.dart';

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
  String _ytRegion = 'US';

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
    // Detect region from locale
    String region = 'US';
    try {
      final locale = Localizations.localeOf(context);
      if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
        region = locale.countryCode!.toUpperCase();
      }
    } catch (_) {}
    setState(() { _ytLoading = true; _ytRegion = region; });
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

  Future<void> _shareVideo(BuildContext context, Video video) async {
    String url;
    if (kIsWeb) {
      final uri = Uri.base;
      final isDefaultPort = (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      final origin = '${uri.scheme}://${uri.host}${isDefaultPort ? '' : ':${uri.port}'}';
      url = '$origin/watch/${video.id}';
    } else {
      url = '${ApiConfig.baseUrl}/watch/${video.id}';
    }

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link copied to clipboard')));
      }
    } else {
      await Share.share('${video.title}\n$url');
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _suggestions = [];
      _searchActive = false;
    });
    context.read<VideoProvider>().setSearch('');
  }

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
                  Text('VidMez', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
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
                          builder: (_) => const ChangePasswordScreen()),
                    );
                  } else if (value == 'bookmarks') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BookmarksScreen()),
                    );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      auth.user!.email,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'bookmarks',
                    child: Row(
                      children: [
                        Icon(Icons.bookmark_border, size: 18),
                        SizedBox(width: 8),
                        Text('Bookmarks'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'change_password',
                    child: Row(
                      children: [
                        Icon(Icons.lock_reset, size: 18),
                        SizedBox(width: 8),
                        Text('Change Password'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18),
                        SizedBox(width: 8),
                        Text('Log Out'),
                      ],
                    ),
                  ),
                ],
              ),
            ] else
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
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
                            title: Text(
                              s['title'] as String,
                              style: const TextStyle(color: Colors.white),
                            ),
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

  Widget _buildBody(VideoProvider videoProvider) {
    if (videoProvider.loading && videoProvider.videos.isEmpty && _ytLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (videoProvider.error != null && videoProvider.videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(videoProvider.error!,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // ── YouTube Trending shelf ──────────────────────────────────────────
        SliverToBoxAdapter(child: _buildYouTubeShelf()),

        // ── VidMez section header ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    color: Color(0xFF1E88E5), size: 20),
                const SizedBox(width: 8),
                const Text('VidMez Videos',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                if (videoProvider.loading && videoProvider.videos.isNotEmpty)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        ),

        // ── VidMez video grid ───────────────────────────────────────────────
        if (videoProvider.videos.isEmpty && !videoProvider.loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.video_library_outlined,
                      size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No videos yet. Be the first to upload!',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= videoProvider.videos.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final video = videoProvider.videos[index];
                  return VideoCard(
                    video: video,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              VideoPlayerScreen(videoId: video.id)),
                    ),
                    onShare: () => _shareVideo(context, video),
                  );
                },
                childCount: videoProvider.videos.length +
                    (videoProvider.hasMore ? 1 : 0),
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                childAspectRatio: 1.3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildYouTubeShelf() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Trending on YouTube · $_ytRegion',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_ytLoading)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.red)),
              ],
            ),
          ),

          // Horizontal scroll of cards
          if (_ytLoading && _ytVideos.isEmpty)
            SizedBox(
              height: 175,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                itemBuilder: (_, __) => _skeletonCard(),
              ),
            )
          else if (_ytVideos.isEmpty)
            const SizedBox(
              height: 60,
              child: Center(
                child: Text('YouTube trending unavailable',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _ytVideos.length,
                itemBuilder: (context, index) {
                  final video = _ytVideos[index];
                  return YouTubeVideoCard(
                    video: video,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => YouTubePlayerScreen(video: video)),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
        ],
      ),
    );
  }

  Widget _skeletonCard() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
