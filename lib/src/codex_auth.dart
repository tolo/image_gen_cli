import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// OAuth client id used by the Codex CLI's ChatGPT login flow. Required to
/// refresh access tokens against the OpenAI auth server.
const _codexClientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
const _refreshUrl = 'https://auth.openai.com/oauth/token';

/// Thrown when credentials cannot be loaded or refreshed. [needsRelogin]
/// signals that the refresh token itself is dead and the user must run
/// `codex login` again.
class AuthException implements Exception {
  AuthException(this.message, {this.needsRelogin = false});
  final String message;
  final bool needsRelogin;
  @override
  String toString() => message;
}

/// Credentials read from a Codex `auth.json`, plus the ability to refresh and
/// persist the OAuth tokens back to that file.
///
/// Two auth shapes are supported:
///  - `chatgpt`: OAuth tokens ([accessToken]/[refreshToken]/[accountId]) used
///    against the ChatGPT backend.
///  - an `OPENAI_API_KEY` present in the file (or supplied out of band), used
///    against the public API.
class CodexCredentials {
  CodexCredentials._(this._file, this._raw);

  final File _file;
  final Map<String, dynamic> _raw;

  String? get apiKey =>
      (_raw['OPENAI_API_KEY'] as String?)?.trim().isEmpty ?? true ? null : (_raw['OPENAI_API_KEY'] as String).trim();

  String get authMode => (_raw['auth_mode'] as String?) ?? 'unknown';

  Map<String, dynamic> get _tokens => (_raw['tokens'] as Map?)?.cast<String, dynamic>() ?? const {};

  String? get accessToken => _tokens['access_token'] as String?;
  String? get refreshToken => _tokens['refresh_token'] as String?;
  String? get accountId => _tokens['account_id'] as String?;

  bool get hasOAuth => accessToken != null && accountId != null;

  /// Loads credentials from [path] (defaults to `~/.codex/auth.json`).
  static Future<CodexCredentials> load(String? path) async {
    final resolved = path ?? _defaultAuthPath();
    final file = File(resolved);
    if (!file.existsSync()) {
      throw AuthException(
        'No Codex credentials found at $resolved.\n'
        'Run `codex login` first, or pass --api-key / set OPENAI_API_KEY.',
      );
    }
    final Map<String, dynamic> raw;
    try {
      raw = (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
    } catch (e) {
      throw AuthException('Could not parse $resolved as JSON: $e');
    }
    return CodexCredentials._(file, raw);
  }

  /// Returns a valid access token, refreshing first if the current one is
  /// expired or about to expire (within [skew]). Persists refreshed tokens.
  Future<String> validAccessToken({Duration skew = const Duration(minutes: 1)}) async {
    if (!hasOAuth) {
      throw AuthException('No ChatGPT OAuth tokens present in auth file.');
    }
    if (_isExpired(accessToken!, skew)) {
      await refresh();
    }
    return accessToken!;
  }

  /// Forces a token refresh against the OpenAI auth server and persists the
  /// new tokens back to the auth file.
  Future<void> refresh() async {
    final token = refreshToken;
    if (token == null) {
      throw AuthException('No refresh_token available; run `codex login`.', needsRelogin: true);
    }
    final resp = await http.post(
      Uri.parse(_refreshUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': _codexClientId,
        'grant_type': 'refresh_token',
        'refresh_token': token,
      }),
    );
    if (resp.statusCode != 200) {
      final code = _errorCode(resp.body);
      final dead =
          code != null && (code.contains('expired') || code.contains('reused') || code.contains('invalidated'));
      throw AuthException(
        'Token refresh failed (${resp.statusCode})'
        '${code != null ? ': $code' : ''}.'
        '${dead ? '\nRefresh token is no longer valid — run `codex login`.' : ''}',
        needsRelogin: dead,
      );
    }
    final data = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    final tokens = Map<String, dynamic>.from(_tokens);
    for (final key in ['access_token', 'refresh_token', 'id_token']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) tokens[key] = v;
    }
    _raw['tokens'] = tokens;
    _raw['last_refresh'] = DateTime.now().toUtc().toIso8601String();
    await _persist();
  }

  /// Atomically rewrites the auth file (mode 0600), preserving any fields this
  /// tool does not understand.
  Future<void> _persist() async {
    final tmp = File('${_file.path}.tmp-$pid');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(_raw));
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', tmp.path]);
    }
    await tmp.rename(_file.path);
  }

  static String _defaultAuthPath() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.codex/auth.json';
  }

  /// Decodes a JWT's `exp` claim (no signature verification — we only read the
  /// expiry) and reports whether it lapses within [skew].
  static bool _isExpired(String jwt, Duration skew) {
    final parts = jwt.split('.');
    if (parts.length != 3) return false; // not a JWT we can read; assume usable
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      return DateTime.now().toUtc().add(skew).isAfter(expiry);
    } catch (_) {
      return false;
    }
  }

  static String? _errorCode(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        final err = m['error'];
        if (err is Map) return (err['code'] ?? err['type'])?.toString();
        if (err is String) return err;
      }
    } catch (_) {}
    return null;
  }
}
