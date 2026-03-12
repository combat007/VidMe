import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Returns the API base URL.
  ///
  /// Priority:
  ///   1. --dart-define=API_BASE_URL=...  (explicit override, e.g. production)
  ///   2. On web: current browser origin read at runtime via Uri.base
  ///              → works from localhost, LAN IP, or any hostname without rebuilding
  ///   3. Mobile fallback: http://localhost:3000
  static String get baseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) return defined;

    if (kIsWeb) {
      // Uri.base is the current page URL (e.g. http://192.168.1.17or http://localhost).
      // We extract just the scheme+host+port so Dio gets a valid absolute base URL.
      // nginx already proxies /api/ → backend:3000 on the same origin.
      final uri = Uri.base;
      final isDefaultPort = (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      return '${uri.scheme}://${uri.host}${isDefaultPort ? '' : ':${uri.port}'}';
    }

    return 'http://localhost:3000';
  }

  static const String ipfsGateway = 'https://ipfs.filebase.io/ipfs';

  // Web: route through nginx (/ipfs/) — makes requests same-origin so
  // video_player_web's crossorigin="anonymous" works without CORS issues.
  // Mobile: direct Filebase URL (no crossorigin attribute, no CORS concern).
  static String videoUrl(String cid) =>
      kIsWeb ? '$baseUrl/ipfs/$cid' : '$ipfsGateway/$cid';

  static String thumbnailUrl(String cid) =>
      kIsWeb ? '$baseUrl/ipfs/$cid' : '$ipfsGateway/$cid';
}
