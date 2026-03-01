import 'package:flutter/foundation.dart';
import '../models/video.dart';
import '../services/api_service.dart';

class VideoProvider extends ChangeNotifier {
  List<Video> _videos = [];
  bool _loading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;
  String _searchQuery = '';

  List<Video> get videos => _videos;
  bool get loading => _loading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  void setSearch(String q) {
    _searchQuery = q;
    loadVideos(refresh: true);
  }

  Future<void> loadVideos({bool refresh = false}) async {
    if (_loading) return;
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _videos = [];
    }
    if (!_hasMore) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.listVideos(
        page: _currentPage,
        limit: 20,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );

      final rawVideos = result['videos'] as List<dynamic>;
      final pagination = result['pagination'] as Map<String, dynamic>;

      final newVideos = rawVideos
          .map((v) => Video.fromJson(v as Map<String, dynamic>))
          .toList();

      _videos = refresh ? newVideos : [..._videos, ...newVideos];
      _currentPage++;
      _hasMore = _currentPage <= (pagination['totalPages'] as int);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
