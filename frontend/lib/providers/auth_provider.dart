import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Returned by [loginWithGoogle] and [loginWithGitHub].
/// If [needsAge] is true the caller must push OAuthAgeScreen with [pendingToken] and [email].
class OAuthResult {
  final bool needsAge;
  final String? pendingToken;
  final String? email;
  const OAuthResult({this.needsAge = false, this.pendingToken, this.email});
}

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _error;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _user?.isAdmin ?? false;

  // ── Google Sign-In instance ─────────────────────────────────────────────────
  // clientId / serverClientId are set via --dart-define=GOOGLE_CLIENT_ID=...
  // • Web: clientId enables the JS SDK popup
  // • Mobile: serverClientId requests a verifiable ID token from Play Services
  //   (also requires google-services.json + SHA-1 registered in Google Cloud Console)
  static const _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  final _googleSignIn = GoogleSignIn(
    clientId: kIsWeb && _googleClientId.isNotEmpty ? _googleClientId : null,
    serverClientId: !kIsWeb && _googleClientId.isNotEmpty ? _googleClientId : null,
    scopes: ['email', 'profile'],
  );

  // ── init ────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final token = await StorageService.getToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      _user = await ApiService.getMe();
      _status = AuthStatus.authenticated;
    } catch (_) {
      await StorageService.deleteToken();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ── email/password ──────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _error = null;
    try {
      final result = await ApiService.login(email: email, password: password);
      await StorageService.saveToken(result['token'] as String);
      _user = User.fromJson(result['user'] as Map<String, dynamic>);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required int age,
    required String captchaId,
    required int captchaAnswer,
  }) async {
    _error = null;
    try {
      final result = await ApiService.signup(
        email: email, password: password, age: age,
        captchaId: captchaId, captchaAnswer: captchaAnswer,
      );
      await StorageService.saveToken(result['token'] as String);
      _user = User.fromJson(result['user'] as Map<String, dynamic>);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Google OAuth ────────────────────────────────────────────────────────────

  Future<OAuthResult?> loginWithGoogle() async {
    _error = null;
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return null; // user cancelled

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        _error = 'Could not get Google credentials. '
            'Ensure GOOGLE_CLIENT_ID is set and the app is registered in Google Cloud Console.';
        notifyListeners();
        return null;
      }

      final result = await ApiService.googleAuth(idToken: idToken);
      return _handleOAuthResult(result);
    } catch (e) {
      _error = 'Google sign-in failed: $e';
      notifyListeners();
      return null;
    }
  }

  // ── GitHub OAuth ────────────────────────────────────────────────────────────

  Future<OAuthResult?> loginWithGitHub() async {
    _error = null;
    try {
      final platform = kIsWeb ? 'web' : 'mobile';
      final url = '${ApiConfig.baseUrl}/api/auth/github?platform=$platform';

      // On web: popup → oauth-callback.html posts back the URL via postMessage
      // On mobile: Chrome Custom Tab → backend redirects to vidmez:// deep link
      final callbackScheme = kIsWeb
          ? '${Uri.base.origin}/oauth-callback.html'
          : 'vidmez';

      final resultUrl = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
      );

      final uri = Uri.parse(resultUrl);
      final params = uri.queryParameters;

      if (params.containsKey('error')) {
        _error = params['error'];
        notifyListeners();
        return null;
      }

      if (params.containsKey('token')) {
        await _storeAndFetch(params['token']!);
        return const OAuthResult(needsAge: false);
      }

      if (params.containsKey('pending')) {
        return OAuthResult(
          needsAge: true,
          pendingToken: params['pending'],
          email: params['email'],
        );
      }

      _error = 'GitHub sign-in failed: unexpected response';
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'GitHub sign-in failed: $e';
      notifyListeners();
      return null;
    }
  }

  // ── OAuth age completion ────────────────────────────────────────────────────

  Future<bool> completeOAuth({required String pendingToken, required int age}) async {
    _error = null;
    try {
      final result = await ApiService.oauthComplete(pendingToken: pendingToken, age: age);
      await _storeAndFetch(result['token'] as String);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── logout ──────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await StorageService.deleteToken();
    try { await _googleSignIn.signOut(); } catch (_) {}
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── private helpers ─────────────────────────────────────────────────────────

  OAuthResult _handleOAuthResult(Map<String, dynamic> result) {
    if (result['needsAge'] == true) {
      return OAuthResult(
        needsAge: true,
        pendingToken: result['pendingToken'] as String,
        email: result['email'] as String?,
      );
    }
    // Existing user — token is in the response
    final token = result['token'] as String?;
    final userData = result['user'] as Map<String, dynamic>?;
    if (token != null && userData != null) {
      StorageService.saveToken(token);
      _user = User.fromJson(userData);
      _status = AuthStatus.authenticated;
      notifyListeners();
    }
    return const OAuthResult(needsAge: false);
  }

  Future<void> _storeAndFetch(String token) async {
    await StorageService.saveToken(token);
    _user = await ApiService.getMe();
    _status = AuthStatus.authenticated;
    notifyListeners();
  }
}
