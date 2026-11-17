import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'cloud_config.dart';
import 'settings_service.dart';

/// Google sign-in for SpokenLog cloud. Produces the Google ID token the
/// server verifies; the account's `sub` is the user ID for credits and ads.
///
/// Android uses Credential Manager (google_sign_in). Windows and macOS use
/// the OAuth loopback flow with PKCE in the system browser and keep the
/// refresh token in secure storage.
class CloudAccountService {
  CloudAccountService({
    required this._settings,
    CloudConfig? config,
    http.Client? client,
  })  : _config = config ?? CloudConfig.current,
        _client = client ?? http.Client();

  final SettingsService _settings;
  final CloudConfig _config;
  final http.Client _client;

  String? _idToken;
  bool _androidReady = false;

  /// Google account ID of the current token, used for ad rewards.
  String? get userId => _claims(_idToken)?['sub'] as String?;

  String? get email => _claims(_idToken)?['email'] as String?;

  /// A valid ID token, signing in silently when possible. With
  /// [interactive], shows Google's sign-in UI if needed. Null means signed out.
  Future<String?> idToken({bool interactive = false}) async {
    if (_fresh(_idToken)) return _idToken;
    _idToken = Platform.isAndroid
        ? await _androidToken(interactive)
        : await _desktopToken(interactive);
    return _idToken;
  }

  Future<void> signOut() async {
    _idToken = null;
    if (Platform.isAndroid) {
      await _initAndroid();
      await GoogleSignIn.instance.signOut();
    } else {
      await _settings.setCloudRefreshToken(null);
    }
  }

  Future<void> _initAndroid() async {
    if (_androidReady) return;
    await GoogleSignIn.instance.initialize(serverClientId: _config.androidServerClientId);
    _androidReady = true;
  }

  Future<String?> _androidToken(bool interactive) async {
    await _initAndroid();
    var account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null && interactive) {
      account = await GoogleSignIn.instance.authenticate();
    }
    return account?.authentication.idToken;
  }

  Future<String?> _desktopToken(bool interactive) async {
    final refresh = await _settings.getCloudRefreshToken();
    if (refresh != null && refresh.isNotEmpty) {
      final token = await _exchange({'grant_type': 'refresh_token', 'refresh_token': refresh});
      if (token != null) return token.idToken;
      // Revoked or expired; fall through to a fresh sign-in.
      await _settings.setCloudRefreshToken(null);
    }
    if (!interactive) return null;
    return _desktopSignIn();
  }

  Future<String?> _desktopSignIn() async {
    final verifier = _randomUrlSafe(48);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomUrlSafe(16);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    try {
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _config.desktopClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': 'openid email',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw const CloudAuthException('브라우저를 열지 못했습니다.');
      }
      final request = await server.first.timeout(const Duration(minutes: 5));
      final params = request.uri.queryParameters;
      final ok = params['state'] == state && params['code'] != null;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('<meta charset="utf-8"><p style="font-family:sans-serif">'
            '${ok ? 'SpokenLog 로그인이 완료되었습니다. 이 창을 닫아도 됩니다.' : '로그인이 취소되었습니다.'}</p>');
      await request.response.close();
      if (!ok) return null;
      final token = await _exchange({
        'grant_type': 'authorization_code',
        'code': params['code']!,
        'code_verifier': verifier,
        'redirect_uri': redirect,
      });
      if (token == null) throw const CloudAuthException('Google 로그인 토큰을 받지 못했습니다.');
      if (token.refreshToken != null) await _settings.setCloudRefreshToken(token.refreshToken);
      return token.idToken;
    } on TimeoutException {
      return null;
    } finally {
      await server.close(force: true);
    }
  }

  Future<({String idToken, String? refreshToken})?> _exchange(Map<String, String> fields) async {
    final response = await _client.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        ...fields,
        'client_id': _config.desktopClientId,
        'client_secret': _config.desktopClientSecret,
      },
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = body['id_token'] as String?;
    if (idToken == null) return null;
    return (idToken: idToken, refreshToken: body['refresh_token'] as String?);
  }

  /// Valid for at least another minute.
  static bool _fresh(String? token) {
    final exp = _claims(token)?['exp'];
    if (exp is! num) return false;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
        .isAfter(DateTime.now().add(const Duration(minutes: 1)));
  }

  /// Reads a JWT payload without verifying it; the server verifies tokens.
  static Map<String, dynamic>? _claims(String? token) {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return null;
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _randomUrlSafe(int bytes) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class CloudAuthException implements Exception {
  const CloudAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
