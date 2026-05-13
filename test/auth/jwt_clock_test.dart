import 'dart:convert';

import 'package:test/test.dart';

import 'package:taglibro_cli/src/auth/jwt_clock.dart';

void main() {
  group('decodeJwtExp', () {
    test('returns the exp claim as a UTC DateTime', () {
      final t = _jwtWithExp(1747999999);
      final exp = decodeJwtExp(t);
      expect(exp, isNotNull);
      expect(exp!.isUtc, isTrue);
      expect(exp.millisecondsSinceEpoch ~/ 1000, 1747999999);
    });

    test('handles base64url payloads that lack `=` padding', () {
      // Real GoTrue tokens strip the `=` padding; base64Url.decode
      // rejects those without explicit normalisation. Force a
      // payload that needs 2 chars of padding to land at exactly
      // that path.
      final t = _jwtWithExtraClaims({'exp': 1747999999, 'pad': 'x'});
      expect(decodeJwtExp(t), isNotNull);
    });

    test('returns null when the token has the wrong segment count', () {
      expect(decodeJwtExp('notajwt'), isNull);
      expect(decodeJwtExp('a.b'), isNull);
      expect(decodeJwtExp('a.b.c.d'), isNull);
    });

    test('returns null when the payload is not base64url', () {
      expect(decodeJwtExp('header.!!!!notb64.sig'), isNull);
    });

    test('returns null when the payload has no exp claim', () {
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'someone'})))
          .replaceAll('=', '');
      expect(decodeJwtExp('hdr.$payload.sig'), isNull);
    });

    test('returns null when exp is non-integer (string or float)', () {
      final p1 = base64Url
          .encode(utf8.encode(jsonEncode({'exp': '1747999999'})))
          .replaceAll('=', '');
      final p2 = base64Url
          .encode(utf8.encode(jsonEncode({'exp': 1.5e9})))
          .replaceAll('=', '');
      expect(decodeJwtExp('hdr.$p1.sig'), isNull);
      expect(decodeJwtExp('hdr.$p2.sig'), isNull);
    });
  });

  group('accessTokenIsFresh', () {
    // Pin a fake "now" for deterministic comparisons.
    final now = DateTime.utc(2026, 5, 13, 12);

    test('returns true when exp is comfortably past the 60s buffer', () {
      final t = _jwtWithExp(_secondsFrom(now, const Duration(hours: 1)));
      expect(accessTokenIsFresh(t, now: now), isTrue);
    });

    test('returns false when exp is inside the 60s buffer', () {
      final t = _jwtWithExp(_secondsFrom(now, const Duration(seconds: 30)));
      expect(accessTokenIsFresh(t, now: now), isFalse);
    });

    test('returns false when exp is in the past', () {
      final t = _jwtWithExp(_secondsFrom(now, -const Duration(minutes: 5)));
      expect(accessTokenIsFresh(t, now: now), isFalse);
    });

    test('returns false when the token does not decode (treat as expired)',
        () {
      expect(accessTokenIsFresh('garbage', now: now), isFalse);
    });

    test('buffer is configurable', () {
      // 30s remaining + 10s buffer → still fresh.
      final t = _jwtWithExp(_secondsFrom(now, const Duration(seconds: 30)));
      expect(
        accessTokenIsFresh(t, buffer: const Duration(seconds: 10), now: now),
        isTrue,
      );
    });
  });
}

// ── Helpers ────────────────────────────────────────────────────────

String _jwtWithExp(int exp) => _jwtWithExtraClaims({'exp': exp});

String _jwtWithExtraClaims(Map<String, dynamic> claims) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  // Header / signature don't matter — decodeJwtExp ignores both.
  final header = enc({'alg': 'HS256', 'typ': 'JWT'});
  final payload = enc(claims);
  return '$header.$payload.sig';
}

int _secondsFrom(DateTime base, Duration offset) =>
    (base.add(offset).millisecondsSinceEpoch ~/ 1000);
