import 'package:flutter/material.dart';
import '../../models/video.dart';
import '../../services/api_service.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  // Stats
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;

  // Videos
  List<Video> _videos = [];
  bool _videosLoading = true;
  bool _hasMore = true;
  int _page = 1;
  final _searchController = TextEditingController();
  String _lastSearch = '';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadVideos(refresh: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        _loadVideos();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getAdminStats();
      if (mounted) setState(() { _stats = stats; _statsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (_videosLoading && !refresh) return;
    if (!_hasMore && !refresh) return;

    final search = _searchController.text.trim();
    if (refresh) {
      setState(() { _videos = []; _page = 1; _hasMore = true; _videosLoading = true; _lastSearch = search; });
    } else if (!_hasMore) return;

    try {
      final data = await ApiService.adminListVideos(
        page: refresh ? 1 : _page,
        search: refresh ? search : _lastSearch,
      );
      final fetched = (data['videos'] as List).map((j) => Video.fromJson(j as Map<String, dynamic>)).toList();
      final pagination = data['pagination'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _videos = refresh ? fetched : [..._videos, ...fetched];
          _page = (refresh ? 1 : _page) + 1;
          _hasMore = _page - 1 < (pagination['totalPages'] as int);
          _videosLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _videosLoading = false);
    }
  }

  Future<void> _blockVideo(Video video) async {
    try {
      await ApiService.adminBlockVideo(video.id);
      setState(() {
        final idx = _videos.indexWhere((v) => v.id == video.id);
        if (idx != -1) {
          _videos[idx] = Video(
            id: video.id, userId: video.userId, user: video.user,
            title: video.title, description: video.description,
            ipfsCid: video.ipfsCid, thumbnailCid: video.thumbnailCid,
            gatewayUrl: video.gatewayUrl, thumbnailUrl: video.thumbnailUrl,
            duration: video.duration, is18Plus: video.is18Plus, blocked: true,
            likesEnabled: video.likesEnabled, commentsEnabled: video.commentsEnabled,
            status: video.status, viewCount: video.viewCount, createdAt: video.createdAt,
            count: video.count,
          );
        }
      });
      _showSnack('Video blocked');
      _loadStats();
    } catch (e) {
      _showSnack('Failed: $e', error: true);
    }
  }

  Future<void> _unblockVideo(Video video) async {
    try {
      await ApiService.adminUnblockVideo(video.id);
      setState(() {
        final idx = _videos.indexWhere((v) => v.id == video.id);
        if (idx != -1) {
          _videos[idx] = Video(
            id: video.id, userId: video.userId, user: video.user,
            title: video.title, description: video.description,
            ipfsCid: video.ipfsCid, thumbnailCid: video.thumbnailCid,
            gatewayUrl: video.gatewayUrl, thumbnailUrl: video.thumbnailUrl,
            duration: video.duration, is18Plus: video.is18Plus, blocked: false,
            likesEnabled: video.likesEnabled, commentsEnabled: video.commentsEnabled,
            status: video.status, viewCount: video.viewCount, createdAt: video.createdAt,
            count: video.count,
          );
        }
      });
      _showSnack('Video unblocked');
      _loadStats();
    } catch (e) {
      _showSnack('Failed: $e', error: true);
    }
  }

  Future<void> _deleteVideo(Video video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Video', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently delete "${video.title}"? This also removes it from IPFS.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.adminDeleteVideo(video.id);
      setState(() => _videos.removeWhere((v) => v.id == video.id));
      _showSnack('Video deleted');
      _loadStats();
    } catch (e) {
      _showSnack('Failed: $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Color(0xFF1E88E5)),
            SizedBox(width: 8),
            Text('Admin Panel'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStats();
          await _loadVideos(refresh: true);
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Stats cards
            SliverToBoxAdapter(child: _buildStats()),
            // Search bar
            SliverToBoxAdapter(child: _buildSearchBar()),
            // Video list header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('All Videos', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
            ),
            // Video list
            if (_videosLoading && _videos.isEmpty)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_videos.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No videos found', style: TextStyle(color: Colors.grey))),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i >= _videos.length) {
                      return _hasMore
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : const SizedBox.shrink();
                    }
                    return _buildVideoTile(_videos[i]);
                  },
                  childCount: _videos.length + (_hasMore ? 1 : 0),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    if (_statsLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_stats == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.2,
        children: [
          _statCard('Users', '${_stats!['totalUsers']}', Icons.people, Colors.blue),
          _statCard('Videos', '${_stats!['totalVideos']}', Icons.video_library, Colors.green),
          _statCard('Blocked', '${_stats!['blockedVideos']}', Icons.block, Colors.orange),
          _statCard('Total Views', '${_stats!['totalViews']}', Icons.visibility, Colors.purple),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search videos by title...',
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    _searchController.clear();
                    _loadVideos(refresh: true);
                  },
                )
              : null,
        ),
        style: const TextStyle(color: Colors.white),
        onSubmitted: (_) => _loadVideos(refresh: true),
      ),
    );
  }

  Widget _buildVideoTile(Video video) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: video.blocked
            ? Border.all(color: Colors.orange.withOpacity(0.6))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: video.thumbnailUrl != null
              ? Image.network(
                  video.thumbnailUrl!,
                  width: 72,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                )
              : _thumbPlaceholder(),
        ),
        title: Row(
          children: [
            if (video.blocked)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text('BLOCKED', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            Expanded(
              child: Text(
                video.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${video.user.email} • ${video.viewCount} views • ${video.formattedDuration}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54),
          color: const Color(0xFF2A2A2A),
          onSelected: (action) {
            switch (action) {
              case 'block': _blockVideo(video);
              case 'unblock': _unblockVideo(video);
              case 'delete': _deleteVideo(video);
            }
          },
          itemBuilder: (_) => [
            if (!video.blocked)
              const PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(Icons.block, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text('Block', style: TextStyle(color: Colors.white)),
                ]),
              )
            else
              const PopupMenuItem(
                value: 'unblock',
                child: Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('Unblock', style: TextStyle(color: Colors.white)),
                ]),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_forever, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 72,
      height: 48,
      color: const Color(0xFF2A2A2A),
      child: const Icon(Icons.video_file, color: Colors.white38, size: 24),
    );
  }
}
