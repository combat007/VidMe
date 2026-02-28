import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/video_provider.dart';
import '../../widgets/video_card.dart';
import '../upload/upload_screen.dart';
import '../video/video_player_screen.dart';
import '../admin/admin_panel_screen.dart';
import '../auth/change_password_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoProvider>().loadVideos(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      context.read<VideoProvider>().loadVideos();
    }
  }

  Future<void> _refresh() async {
    await context.read<VideoProvider>().loadVideos(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final videoProvider = context.watch<VideoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.play_circle_filled, color: Color(0xFF1E88E5)),
            SizedBox(width: 8),
            Text('VidMe', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (auth.isAuthenticated) ...[
            if (auth.isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings, color: Color(0xFFFFB300)),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 18),
                      SizedBox(width: 8),
                      Text('Log Out'),
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
              ],
            ),
          ] else
            TextButton(
              onPressed: () {},
              child: const Text('Log In'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(videoProvider),
      ),
    );
  }

  Widget _buildBody(VideoProvider videoProvider) {
    if (videoProvider.loading && videoProvider.videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (videoProvider.error != null && videoProvider.videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(videoProvider.error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (videoProvider.videos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No videos yet. Be the first to upload!',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        childAspectRatio: 1.3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: videoProvider.videos.length + (videoProvider.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= videoProvider.videos.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final video = videoProvider.videos[index];
        return VideoCard(
          video: video,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoId: video.id),
            ),
          ),
        );
      },
    );
  }
}
