import 'dart:convert';

/// Decode a JWT's `exp` claim without verifying the signature.
///
/// We don't need verification here — the JWT was issued by Supabase
/// during `login`, persisted to disk under mode 0600, and reloaded.
/// The only reason to peek inside is to find out how long the
/// access token has before GoTrue rejects it, so the CLI can skip a
/// network refresh when there's still plenty of life left.
///
/// Returns `null` when the input isn't a parseable JWT, when the
/// payload base64url decode fails, or when the `exp` claim is
/// missing / not an integer. Callers treat that as "behave as
/// expired" so the refresh path runs and surfaces a real error.
DateTime? decodeJwtExp(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    // base64Url.normalize() adds the missing `=` padding the JWT
    // spec strips. Without it, base64Url.decode raises on most
    // real-world tokens.
    final payload = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(payload));
    final json = jsonDecode(decoded);
    if (json is! Map<String, dynamic>) return null;
    final exp = json['exp'];
    if (exp is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}

/// Whether a session built from this access token still has enough
/// life to skip a server-side refresh.
///
/// `now` is injectable so tests can pin the wallclock without
/// fiddling with the system clock. Default uses UTC because GoTrue
/// emits `exp` in unix-epoch seconds (no timezone).
bool accessTokenIsFresh(
  String accessToken, {
  Duration buffer = const Duration(seconds: 60),
  DateTime? now,
}) {
  final exp = decodeJwtExp(accessToken);
  if (exp == null) return false;
  final wall = now ?? DateTime.now().toUtc();
  return exp.isAfter(wall.add(buffer));
}
