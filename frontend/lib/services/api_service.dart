import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/video.dart';
import '../models/comment.dart';
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

  // Auth
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
  }) async {
    final headers = await _authHeaders();
    return _handleRequest<Map<String, dynamic>>(
      _dio.get('/api/videos', queryParameters: {
        'page': page,
        'limit': limit,
        'filter18plus': filter18plus,
      }, options: Options(headers: headers)),
    );
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

  static Future<Map<String, dynamic>> uploadVideoBytes(
    Uint8List bytes,
    String filename, {
    void Function(int, int)? onProgress,
  }) async {
    final headers = await _authHeaders();
    final formData = FormData.fromMap({
      'video': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _handleRequest<Map<String, dynamic>>(
      _dio.post(
        '/api/videos/upload',
        data: formData,
        options: Options(headers: headers),
        onSendProgress: onProgress,
      ),
    );
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
}
