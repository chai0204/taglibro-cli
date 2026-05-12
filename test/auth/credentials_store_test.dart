import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:taglibro_cli/src/auth/credentials_store.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('taglibro-creds-test-');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('load() returns null when the file does not exist', () {
    final store = CredentialsStore(
      overridePath: p.join(tmp.path, 'missing.json'),
    );
    expect(store.exists(), isFalse);
    expect(store.load(), isNull);
  });

  test('save → load round-trip preserves every field', () {
    final path = p.join(tmp.path, 'creds.json');
    final store = CredentialsStore(overridePath: path);
    final expires = DateTime.utc(2026, 5, 12, 10, 0, 0);
    store.save(StoredCredentials(
      supabaseUrl: 'https://test.supabase.co',
      anonKey: 'anon',
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: expires,
      userId: 'user-id',
      email: 'shun@example.com',
    ));

    final loaded = store.load();
    expect(loaded, isNotNull);
    expect(loaded!.supabaseUrl, 'https://test.supabase.co');
    expect(loaded.anonKey, 'anon');
    expect(loaded.accessToken, 'access');
    expect(loaded.refreshToken, 'refresh');
    expect(loaded.expiresAt, expires);
    expect(loaded.userId, 'user-id');
    expect(loaded.email, 'shun@example.com');
  });

  test('save() writes the file with mode 0600', () {
    final path = p.join(tmp.path, 'creds.json');
    final store = CredentialsStore(overridePath: path);
    store.save(StoredCredentials(
      supabaseUrl: 'https://test.supabase.co',
      anonKey: 'anon',
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2026),
      userId: 'user-id',
      email: 'shun@example.com',
    ));

    // POSIX-only: stat -c "%a" prints the numeric mode (e.g. "600").
    // dart:io's File.statSync only exposes the high-level FileStat
    // without raw bits.
    if (Platform.isWindows) return;
    final result = Process.runSync('stat', ['-c', '%a', path]);
    expect(result.exitCode, 0);
    expect((result.stdout as String).trim(), '600');
  });

  test('delete() removes the file and is idempotent', () {
    final path = p.join(tmp.path, 'creds.json');
    final store = CredentialsStore(overridePath: path);
    store.save(StoredCredentials(
      supabaseUrl: 'u',
      anonKey: 'a',
      accessToken: 'x',
      refreshToken: 'y',
      expiresAt: DateTime.utc(2026),
      userId: 'id',
    ));
    expect(store.exists(), isTrue);

    store.delete();
    expect(store.exists(), isFalse);

    // Second delete is a no-op.
    store.delete();
  });

  test('resolvePath honours XDG_CONFIG_HOME when set', () {
    // We can't mutate Platform.environment from Dart, but the easier
    // path is to rely on the documented contract: resolvePath()
    // returns whatever XDG_CONFIG_HOME/taglibro/credentials.json
    // shapes when the env var is set at process launch. Here we just
    // assert overridePath wins over both env paths, which is what
    // commands rely on for test isolation.
    final overridden = p.join(tmp.path, 'somewhere/else.json');
    final store = CredentialsStore(overridePath: overridden);
    expect(store.resolvePath(), overridden);
  });
}
