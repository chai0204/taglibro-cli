import 'package:supabase/supabase.dart';

import '../util/config_resolver.dart';
import 'credentials_store.dart';
import 'jwt_clock.dart';

/// Reason an authenticated session couldn't be obtained — used so
/// the top-level CLI can map to the right exit code instead of
/// surfacing a raw exception.
enum AuthFailureKind {
  /// No credentials file at all. exit 2.
  notLoggedIn,

  /// Refresh attempted but the server rejected the refresh_token
  /// (typically `invalid_grant`). exit 3.
  sessionExpired,

  /// Network / unexpected. exit 5.
  serverError,
}

class AuthFailure implements Exception {
  final AuthFailureKind kind;
  final String message;
  const AuthFailure(this.kind, this.message);

  @override
  String toString() => 'AuthFailure(${kind.name}): $message';
}

/// Owns the Supabase client and the credentials lifecycle for CLI
/// commands. Construct once per CLI invocation via [forEnv]; callers
/// use [signedInClient] to get a ready-to-use [SupabaseClient] whose
/// session is guaranteed fresh (refresh is run when the access_token
/// has <60s of life left).
class AuthService {
  final CliConfig _config;
  final CredentialsStore _store;

  AuthService({required CliConfig config, CredentialsStore? store})
      : _config = config,
        _store = store ?? const CredentialsStore();

  factory AuthService.forEnv({String env = 'prod', CredentialsStore? store}) {
    return AuthService(
      config: ConfigResolver.resolve(env: env),
      store: store,
    );
  }

  CliConfig get config => _config;
  CredentialsStore get store => _store;

  /// Returns a [SupabaseClient] with a fresh session attached.
  /// Throws [AuthFailure] when credentials are absent / expired.
  ///
  /// Refresh strategy (audit H1 fix):
  ///   - access_token's JWT `exp` > 60 s ahead → skip GoTrue entirely
  ///     and attach the saved access_token as a static `Authorization`
  ///     header on the SupabaseClient. No network refresh runs, so the
  ///     server doesn't rotate the refresh_token; the disk's
  ///     refresh_token stays valid for the next invocation.
  ///   - access_token ≤ 60 s remaining (or unparseable) → call
  ///     `setSession(refresh_token)`, which DOES refresh, and persist
  ///     the rotated session back to disk so the next call sees the
  ///     new refresh_token.
  ///
  /// The previous implementation called `setSession` unconditionally
  /// and only persisted on the "expired" branch — every CLI command
  /// quietly rotated the refresh_token but never wrote the new one
  /// home, forcing a re-login on the second invocation past GoTrue's
  /// reuse interval (~10 s).
  Future<SupabaseClient> signedInClient() async {
    final creds = _store.load();
    if (creds == null) {
      throw const AuthFailure(
        AuthFailureKind.notLoggedIn,
        'Not logged in. Run `tgl login` first.',
      );
    }

    if (accessTokenIsFresh(creds.accessToken)) {
      return SupabaseClient(
        creds.supabaseUrl,
        creds.anonKey,
        headers: {'Authorization': 'Bearer ${creds.accessToken}'},
      );
    }

    final client = SupabaseClient(creds.supabaseUrl, creds.anonKey);
    try {
      final res = await client.auth.setSession(creds.refreshToken);
      final session = res.session;
      if (session == null) {
        throw const AuthFailure(
          AuthFailureKind.sessionExpired,
          'Session expired. Run `tgl login` to sign in again.',
        );
      }
      _persist(creds, session);
      return client;
    } on AuthException catch (e) {
      throw AuthFailure(AuthFailureKind.sessionExpired,
          'Session expired: ${e.message}. Run `tgl login`.');
    } catch (e) {
      throw AuthFailure(AuthFailureKind.serverError,
          'Could not refresh session: $e');
    }
  }

  /// Performs an email/password sign-in and persists the session.
  /// Returns the email confirmed by the server.
  Future<String> loginWithPassword({
    required String email,
    required String password,
  }) async {
    final client = SupabaseClient(_config.supabaseUrl, _config.anonKey);
    final res =
        await client.auth.signInWithPassword(email: email, password: password);
    final session = res.session;
    final user = res.user;
    if (session == null || user == null) {
      throw const AuthFailure(
        AuthFailureKind.serverError,
        'Login succeeded but the server returned no session — '
        'check Supabase email confirmation settings.',
      );
    }
    _store.save(StoredCredentials(
      supabaseUrl: _config.supabaseUrl,
      anonKey: _config.anonKey,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? '',
      expiresAt: _expiresAt(session),
      userId: user.id,
      email: user.email,
    ));
    return user.email ?? email;
  }

  /// Best-effort server-side logout, then drop the local file.
  /// Local delete always runs even if the server call fails — the
  /// user's intent is "forget me on this machine".
  Future<void> logout() async {
    final creds = _store.load();
    if (creds != null) {
      try {
        final client = SupabaseClient(creds.supabaseUrl, creds.anonKey);
        await client.auth.setSession(creds.refreshToken);
        await client.auth.signOut();
      } catch (_) {
        // Network down / refresh dead — we still want to forget locally.
      }
    }
    _store.delete();
  }

  void _persist(StoredCredentials prev, Session session) {
    _store.save(prev.copyWith(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken ?? prev.refreshToken,
      expiresAt: _expiresAt(session),
    ));
  }

  static DateTime _expiresAt(Session session) {
    // GoTrue exposes `expiresAt` as a unix-epoch second.
    final epoch = session.expiresAt;
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    }
    // Fall back to expiresIn (seconds from now), defaulting to 1 hour
    // — GoTrue's standard. Both fields are populated by the server
    // response in practice; this is defensive only.
    final seconds = session.expiresIn ?? 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }
}
