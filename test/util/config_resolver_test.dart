import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/config_resolver.dart';

void main() {
  group('ConfigResolver.resolve — env vars', () {
    test('uses SUPABASE_URL + SUPABASE_ANON_KEY when both set', () {
      final cfg = ConfigResolver.resolve(
        env: 'prod',
        environment: const {
          'SUPABASE_URL': 'https://from-env.supabase.co',
          'SUPABASE_ANON_KEY': 'env-anon-key',
        },
        startDir: '/tmp/no-repo-here',
      );
      expect(cfg.supabaseUrl, 'https://from-env.supabase.co');
      expect(cfg.anonKey, 'env-anon-key');
      expect(cfg.env, 'prod');
    });

    test('falls through to repo config when env vars are empty', () async {
      final dir = await _makeFakeRepo();
      try {
        final cfg = ConfigResolver.resolve(
          env: 'dev',
          environment: const {'SUPABASE_URL': '', 'SUPABASE_ANON_KEY': ''},
          startDir: dir.path,
        );
        expect(cfg.supabaseUrl, 'http://localhost:19000');
        expect(cfg.anonKey, 'dev-key');
        expect(cfg.env, 'dev');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('different --env values pick different config files', () async {
      final dir = await _makeFakeRepo();
      try {
        final dev = ConfigResolver.resolve(
          env: 'dev',
          environment: const {},
          startDir: dir.path,
        );
        final prod = ConfigResolver.resolve(
          env: 'prod',
          environment: const {},
          startDir: dir.path,
        );
        expect(dev.supabaseUrl, isNot(equals(prod.supabaseUrl)));
        expect(dev.anonKey, 'dev-key');
        expect(prod.anonKey, 'prod-key');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('throws StateError when neither env vars nor repo config exist', () {
      expect(
        () => ConfigResolver.resolve(
          env: 'prod',
          environment: const {},
          startDir: '/tmp/definitely-not-a-repo',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// Build a temp dir that looks like the Flutter taglibro repo from
/// ConfigResolver's perspective — a top-level pubspec whose `name:`
/// line matches exactly, plus dev / prod config jsons.
Future<Directory> _makeFakeRepo() async {
  final root = await Directory.systemTemp.createTemp('taglibro-cfg-test-');
  await File(p.join(root.path, 'pubspec.yaml')).writeAsString(
    'name: taglibro\n'
    'description: fake\n',
  );
  final cfg = Directory(p.join(root.path, 'config'))..createSync();
  await File(p.join(cfg.path, 'dev.json')).writeAsString(
    '{"SUPABASE_URL":"http://localhost:19000","SUPABASE_ANON_KEY":"dev-key"}',
  );
  await File(p.join(cfg.path, 'prod.json')).writeAsString(
    '{"SUPABASE_URL":"https://prod.example.supabase.co",'
    '"SUPABASE_ANON_KEY":"prod-key"}',
  );
  return root;
}
