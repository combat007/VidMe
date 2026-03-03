import 'package:flutter/material.dart';
import '../../models/video.dart';
import '../../services/api_service.dart';
import '../../widgets/video_card.dart';
import '../video/video_player_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final _scrollController = ScrollController();

  List<Video> _videos = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBookmarks(refresh: true);
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
      _loadBookmarks();
    }
  }

  Future<void> _loadBookmarks({bool refresh = false}) async {
    if (_loading && !refresh) return;
    if (!_hasMore && !refresh) return;

    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _loading = true);
    }

    try {
      final result = await ApiService.getBookmarks(page: _page);
      final rawVideos = (result['videos'] as List<dynamic>)
          .map((v) => Video.fromJson(v as Map<String, dynamic>))
          .toList();
      final hasMore = result['hasMore'] as bool? ?? false;

      setState(() {
        if (refresh) {
          _videos = rawVideos;
        } else {
          _videos = [..._videos, ...rawVideos];
        }
        _hasMore = hasMore;
        _page++;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadBookmarks(refresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadBookmarks(refresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No bookmarks yet',
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
      itemCount: _videos.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _videos.length) {
          return const Center(child: CircularProgressIndicator());
        }
        final video = _videos[index];
        return VideoCard(
          video: video,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(videoId: video.id),
            ),
          ).then((_) => _loadBookmarks(refresh: true)),
        );
      },
    );
  }
}
