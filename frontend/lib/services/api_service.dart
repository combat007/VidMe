import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/video.dart';
import '../models/comment.dart';
import '../models/youtube_video.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5),
  ));

  // Separate long-timeout client for video uploads (IPFS pin can take 20+ min)
  static final Dio _uploadDio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
  ));

  static Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    if (token != null) {
      return {'Authorization': 'Bearer $token'};
    }
    return {};
  }

  static Future<T> _handleRequest<T>(Future<Response> request) async {
    try {
      final response = await request;
      return response.data as T;
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['error'] != null)
          ? data['error'] as String
          : e.message ?? 'Request failed';
      throw ApiException(msg, e.response?.statusCode);
    }
  }

  // ── OAuth ──────────────────────────────────────────────────────────────────

  /// Verify a Google ID token on the backend.
  /// Returns { token, user } for existing users, or { needsAge, pendingToken, email } for new ones.
  static Future<Map<String, dynamic>> googleAuth({required String idToken}) async {
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/auth/google', data: {'idToken': idToken}),
    );
  }

  /// Complete OAuth sign-up by supplying the user's age.
  /// Returns { token, user }.
  static Future<Map<String, dynamic>> oauthComplete({
    required String pendingToken,
    required int age,
  }) async {
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/auth/oauth/complete', data: {'pendingToken': pendingToken, 'age': age}),
    );
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getCaptcha() async {
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/auth/captcha'),
    );
  }

  static Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required int age,
    required String captchaId,
    required int captchaAnswer,
  }) async {
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/auth/signup', data: {
        'email': email,
        'password': password,
        'age': age,
        'captchaId': captchaId,
        'captchaAnswer': captchaAnswer,
      }),
    );
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      }),
    );
  }

  static Future<User> getMe() async {
    final headers = await _authHeaders();
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/auth/me', options: Options(headers: headers)),
    );
    return User.fromJson(data);
  }

  // Videos
  static Future<Map<String, dynamic>> listVideos({
    int page = 1,
    int limit = 20,
    bool filter18plus = false,
    String? search,
  }) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/videos', queryParameters: {
        'page': page,
        'limit': limit,
        'filter18plus': filter18plus,
        if (search != null && search.isNotEmpty) 'search': search,
      }, options: Options(headers: headers)),
    );
  }

  static Future<List<Map<String, dynamic>>> getSearchSuggestions(String q) async {
    final data = await _handleRequest<List<dynamic>>(
      _dio.get('/api/videos/suggestions', queryParameters: {'q': q}),
    );
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Video> getVideo(String id) async {
    final headers = await _authHeaders();
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/videos/$id', options: Options(headers: headers)),
    );
    return Video.fromJson(data);
  }

  static Future<Map<String, dynamic>> uploadThumbnailBytes(
    Uint8List bytes,
    String filename,
  ) async {
    final headers = await _authHeaders();
    final formData = FormData.fromMap({
      'thumbnail': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _handleRequest<Map<String, dynamic>>(
      _dio.post(
        '/api/videos/upload-thumbnail',
        data: formData,
        options: Options(headers: headers),
      ),
    );
  }

  // 10 MB per chunk — keeps each request well under any proxy timeout
  static const int _chunkSize = 10 * 1024 * 1024;

  static Future<Map<String, dynamic>> uploadVideoBytes(
    Uint8List bytes,
    String filename, {
    void Function(int, int)? onProgress,
  }) async {
    final headers = await _authHeaders();
    final totalSize = bytes.length;
    final totalChunks = (totalSize / _chunkSize).ceil().clamp(1, 9999);
    final uploadId = '${DateTime.now().millisecondsSinceEpoch}';
    int bytesSent = 0;

    try {
      for (int i = 0; i < totalChunks; i++) {
        final start = i * _chunkSize;
        final end = (start + _chunkSize).clamp(0, totalSize);
        final chunk = bytes.sublist(start, end);

        final formData = FormData.fromMap({
          'chunk': MultipartFile.fromBytes(chunk, filename: 'chunk_$i'),
          'uploadId': uploadId,
          'chunkIndex': i.toString(),
          'totalChunks': totalChunks.toString(),
        });

        await _uploadDio.post(
          '/api/videos/upload-chunk',
          data: formData,
          options: Options(headers: headers),
          onSendProgress: (sent, total) {
            if (onProgress != null && total > 0) {
              onProgress(bytesSent + sent, totalSize);
            }
          },
        );

        bytesSent = end;
        onProgress?.call(bytesSent, totalSize);
      }

      // All chunks received — ask server to assemble + pin to IPFS
      final response = await _uploadDio.post(
        '/api/videos/finalize-upload',
        data: {
          'uploadId': uploadId,
          'totalChunks': totalChunks,
          'filename': filename,
        },
        options: Options(headers: headers),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['error'] != null)
          ? data['error'] as String
          : e.message ?? 'Upload failed';
      throw ApiException(msg, e.response?.statusCode);
    }
  }

  static Future<Video> createVideo({
    required String title,
    String? description,
    required String ipfsCid,
    String? thumbnailCid,
    required int duration,
    required bool is18Plus,
    required bool likesEnabled,
    required bool commentsEnabled,
  }) async {
    final headers = await _authHeaders();
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/videos', data: {
        'title': title,
        'description': description,
        'ipfsCid': ipfsCid,
        'thumbnailCid': thumbnailCid,
        'duration': duration,
        'is18Plus': is18Plus,
        'likesEnabled': likesEnabled,
        'commentsEnabled': commentsEnabled,
      }, options: Options(headers: headers)),
    );
    return Video.fromJson(data);
  }

  static Future<Video> updateVideo(String id, Map<String, dynamic> updates) async {
    final headers = await _authHeaders();
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.patch('/api/videos/$id', data: updates,
          options: Options(headers: headers)),
    );
    return Video.fromJson(data);
  }

  static Future<void> deleteVideo(String id) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.delete('/api/videos/$id', options: Options(headers: headers)),
    );
  }

  // Likes
  static Future<Map<String, dynamic>> toggleLike(String videoId) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/videos/$videoId/like', options: Options(headers: headers)),
    );
  }

  static Future<Map<String, dynamic>> getLikes(String videoId) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/videos/$videoId/likes', options: Options(headers: headers)),
    );
  }

  // Comments
  static Future<Map<String, dynamic>> getComments(String videoId,
      {int page = 1, int limit = 20}) async {
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/videos/$videoId/comments',
          queryParameters: {'page': page, 'limit': limit}),
    );
    return data;
  }

  static Future<Comment> addComment(String videoId, String content) async {
    final headers = await _authHeaders();
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/videos/$videoId/comments',
          data: {'content': content}, options: Options(headers: headers)),
    );
    return Comment.fromJson(data);
  }

  static Future<void> deleteComment(String videoId, String commentId) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.delete('/api/videos/$videoId/comments/$commentId',
          options: Options(headers: headers)),
    );
  }

  // Bookmarks
  static Future<Map<String, dynamic>> toggleBookmark(String videoId) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.post('/api/bookmarks/$videoId', options: Options(headers: headers)),
    );
  }

  static Future<Map<String, dynamic>> getBookmarkStatus(String videoId) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/bookmarks/$videoId', options: Options(headers: headers)),
    );
  }

  static Future<Map<String, dynamic>> getBookmarks({int page = 1, int limit = 20}) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/bookmarks', queryParameters: {'page': page, 'limit': limit},
          options: Options(headers: headers)),
    );
  }

  // Admin
  // Password reset
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.post('/api/auth/change-password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }, options: Options(headers: headers)),
    );
  }

  static Future<void> forgotPassword(String email) async {
    await _handleRequest(
      _dio.post('/api/auth/forgot-password', data: {'email': email}),
    );
  }

  static Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _handleRequest(
      _dio.post('/api/auth/reset-password', data: {
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
      }),
    );
  }

  static Future<Map<String, dynamic>> getAdminStats() async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/admin/stats', options: Options(headers: headers)),
    );
  }

  static Future<Map<String, dynamic>> adminListVideos({
    int page = 1,
    int limit = 20,
    String search = '',
  }) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/admin/videos', queryParameters: {
        'page': page,
        'limit': limit,
        if (search.isNotEmpty) 'search': search,
      }, options: Options(headers: headers)),
    );
  }

  static Future<void> adminDeleteVideo(String id) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.delete('/api/admin/videos/$id', options: Options(headers: headers)),
    );
  }

  static Future<void> adminBlockVideo(String id) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.patch('/api/admin/videos/$id/block', options: Options(headers: headers)),
    );
  }

  static Future<void> adminUnblockVideo(String id) async {
    final headers = await _authHeaders();
    await _handleRequest(
      _dio.patch('/api/admin/videos/$id/unblock', options: Options(headers: headers)),
    );
  }

  // ── YouTube ─────────────────────────────────────────────────────────────────

  static Future<List<YouTubeVideo>> getYouTubeTrending({
    String regionCode = 'US',
    int maxResults = 20,
    String categoryId = '',
  }) async {
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/youtube/trending', queryParameters: {
        'regionCode': regionCode,
        'maxResults': maxResults,
        if (categoryId.isNotEmpty) 'categoryId': categoryId,
      }),
    );
    final items = data['videos'] as List<dynamic>? ?? [];
    return items
        .map((e) => YouTubeVideo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getYouTubeCategories({
    String regionCode = 'US',
  }) async {
    final data = await _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/youtube/categories', queryParameters: {
        'regionCode': regionCode,
      }),
    );
    final items = data['categories'] as List<dynamic>? ?? [];
    return items.cast<Map<String, dynamic>>();
  }
}
