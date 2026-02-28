import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _tokenKey = 'vidme_jwt_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // In-memory fallback for when flutter_secure_storage is unavailable
  // (e.g., HTTP origins where Web Crypto API is not accessible).
  // Token is lost on page refresh in this mode, which is acceptable for
  // non-secure testing environments.
  static String? _memoryToken;

  static Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      _memoryToken = token; // keep in sync
    } catch (_) {
      _memoryToken = token;
    }
  }

  static Future<String?> getToken() async {
    try {
      final stored = await _storage.read(key: _tokenKey);
      if (stored != null) {
        _memoryToken = stored;
        return stored;
      }
    } catch (_) {}
    return _memoryToken;
  }

  static Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    _memoryToken = null;
  }
}
