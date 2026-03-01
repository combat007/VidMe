import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:app_links/app_links.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../utils/platform_utils.dart'
    if (dart.library.html) '../utils/platform_utils_web.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Returned by [loginWithGoogle] and [loginWithGitHub] on mobile.
/// If [needsAge] is true the caller must push OAuthAgeScreen.
class OAuthResult {
  final bool needsAge;
  final String? pendingToken;
  final String? email;
  const OAuthResult({this.needsAge = false, this.pendingToken, this.email});
}

/// Holds pending OAuth state for new web users who still need to supply age.
/// Set by [initialize] when the page loads with oauth_pending URL params.
class OAuthPendingData {
  final String pendingToken;
  final String email;
  const OAuthPendingData({required this.pendingToken, required this.email});
}

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _error;
  OAuthPendingData? _oauthPending;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _user?.isAdmin ?? false;
  OAuthPendingData? get oauthPending => _oauthPending;

  void clearOAuthPending() {
    _oauthPending = null;
    notifyListeners();
  }

  // ── Google Sign-In instance (mobile only) ───────────────────────────────────
  static const _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  final _googleSignIn = GoogleSignIn(
    clientId: kIsWeb && _googleClientId.isNotEmpty ? _googleClientId : null,
    serverClientId: !kIsWeb && _googleClientId.isNotEmpty ? _googleClientId : null,
    scopes: ['email', 'profile'],
  );

  // ── init ────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // Web: check if we landed here from an OAuth redirect
    if (kIsWeb) {
      final uri = Uri.base;
      final oauthToken   = uri.queryParameters['oauth_token'];
      final oauthPending = uri.queryParameters['oauth_pending'];
      final oauthEmail   = uri.queryParameters['oauth_email'];
      final oauthError   = uri.queryParameters['oauth_error'];

      if (oauthToken != null) {
        cleanOAuthUrlParams();
        await _storeAndFetch(oauthToken);
        return;
      }
      if (oauthPending != null) {
        cleanOAuthUrlParams();
        _oauthPending = OAuthPendingData(
          pendingToken: oauthPending,
          email: oauthEmail ?? '',
        );
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
      if (oauthError != null) {
        cleanOAuthUrlParams();
        _error = Uri.decodeComponent(oauthError);
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return;
      }
    }

    // Mobile: check if app was launched via OAuth deep link
    // (handles the case where the OS killed the app during the OAuth flow so
    //  FlutterWebAuth2.authenticate() never resolved in the old process)
    try {
      final uri = await AppLinks().getInitialLink();
      if (uri != null && uri.scheme == 'vidmez') {
        final params = uri.queryParameters;
        if (params.containsKey('token')) {
          await _storeAndFetch(params['token']!);
          return;
        }
        if (params.containsKey('pending')) {
          _oauthPending = OAuthPendingData(
            pendingToken: params['pending']!,
            email: params['email'] ?? '',
          );
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return;
        }
        if (params.containsKey('error')) {
          _error = params['error'];
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return;
        }
      }
    } catch (_) {}

    // Normal init: restore session from stored token
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
      if (kIsWeb) {
        // Web: full-page redirect — the backend handles the OAuth flow and
        // redirects back to /?oauth_token=... which initialize() picks up.
        navigateToUrl('${ApiConfig.baseUrl}/api/auth/google?platform=web');
        // Page navigates away; this future never resolves in practice.
        await Future.delayed(const Duration(minutes: 10));
        return null;
      } else {
        // Mobile: use google_sign_in (Play Services)
        final account = await _googleSignIn.signIn();
        if (account == null) return null;

        final auth = await account.authentication;
        final idToken = auth.idToken;
        if (idToken == null) {
          _error = 'Could not get Google credentials. '
              'Ensure GOOGLE_CLIENT_ID is set and SHA-1 is registered.';
          notifyListeners();
          return null;
        }
        final result = await ApiService.googleAuth(idToken: idToken);
        return _handleOAuthResult(result);
      }
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
      if (kIsWeb) {
        // Web: full-page redirect (same pattern as Google)
        navigateToUrl('${ApiConfig.baseUrl}/api/auth/github?platform=web');
        await Future.delayed(const Duration(minutes: 10));
        return null;
      } else {
        // Mobile: Chrome Custom Tab → vidmez:// deep link
        const callbackScheme = 'vidmez';
        final url = '${ApiConfig.baseUrl}/api/auth/github?platform=mobile';

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
      }
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
      _oauthPending = null; // clear pending state
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
    _oauthPending = null;
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
