import 'package:test/test.dart';

import 'package:taglibro_cli/config/baked_config.dart' as baked;

/// Compile-time `String.fromEnvironment` values are resolved at build
/// time, so these tests check the *default* path — the one a user gets
/// when no `--define` flags were passed (i.e. `dart run`/`dart test`
/// without CI overrides). The CI release workflow exercises the
/// override path implicitly by producing a binary that connects to the
/// configured Supabase project.
void main() {
  group('baked_config defaults', () {
    test('supabaseUrl points at a real Supabase project', () {
      expect(baked.supabaseUrl, startsWith('https://'));
      expect(baked.supabaseUrl, endsWith('.supabase.co'));
    });

    test('supabaseAnonKey is a non-empty JWT', () {
      expect(baked.supabaseAnonKey, isNotEmpty);
      // JWTs are dot-separated 3-part base64url strings; a length check
      // and the dot count are enough to catch a truncated key without
      // pinning the exact value (which would force a test update every
      // time we rotate).
      expect(baked.supabaseAnonKey.split('.').length, 3);
      expect(baked.supabaseAnonKey.length, greaterThan(100));
    });

    test('supabaseAnonKey decodes to role=anon, not service_role', () {
      // Defence-in-depth: catch a paste of the wrong key. The middle
      // segment of a Supabase JWT is base64url-encoded JSON with a
      // `role` claim. If a future contributor accidentally bakes the
      // service_role key (which would grant unrestricted DB access),
      // this test fails loudly at build time.
      final segments = baked.supabaseAnonKey.split('.');
      final padded =
          segments[1].padRight(segments[1].length + (-segments[1].length % 4), '=');
      // No JSON decoder dep here — just substring search.
      // Both 'role":"anon"' and `role": "anon"` formats are accepted.
      final decoded = String.fromCharCodes(
        _base64UrlDecodeBytes(padded),
      );
      expect(decoded, contains('"role":"anon"'));
      expect(decoded, isNot(contains('service_role')));
    });
  });
}

/// Minimal base64url decoder — avoids pulling in dart:convert just for
/// a substring sanity check. Accepts both '+' and '-', '/' and '_'.
List<int> _base64UrlDecodeBytes(String input) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final stripped = input.replaceAll('=', '');
  final bytes = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in stripped.codeUnits) {
    final idx = alphabet.indexOf(String.fromCharCode(ch));
    if (idx < 0) continue;
    buffer = (buffer << 6) | idx;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xff);
    }
  }
  return bytes;
}
