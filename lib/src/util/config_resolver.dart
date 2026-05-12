import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolved Supabase connection target for the CLI.
class CliConfig {
  final String supabaseUrl;
  final String anonKey;
  final String env;

  const CliConfig({
    required this.supabaseUrl,
    required this.anonKey,
    required this.env,
  });
}

/// Resolves the Supabase URL / anon key the CLI should connect to.
///
/// Order of precedence:
///   1. `SUPABASE_URL` + `SUPABASE_ANON_KEY` env vars (highest)
///   2. `<repo-root>/config/<env>.json` from the same Flutter repo
///   3. throws [StateError] with a helpful message
///
/// The anon key is a public key (already baked into Flutter web
/// builds) so reading it from the repo is not a credential leak —
/// see design.md §4.
class ConfigResolver {
  /// Default to prod so a developer running the CLI from anywhere on
  /// disk talks to the same Supabase the Flutter app does.
  ///
  /// [environment] and [startDir] are injectable for tests so they
  /// can exercise the env-var and repo-walk paths without mutating
  /// the real process state.
  static CliConfig resolve({
    String env = 'prod',
    Map<String, String>? environment,
    String? startDir,
  }) {
    final envMap = environment ?? Platform.environment;
    final fromEnv = _fromEnv(env, envMap);
    if (fromEnv != null) return fromEnv;

    final fromFile = _fromRepoConfig(env, startDir);
    if (fromFile != null) return fromFile;

    throw StateError(
      'Could not find Supabase config for env="$env".\n'
      'Either set SUPABASE_URL and SUPABASE_ANON_KEY in the environment,\n'
      'or run the CLI from inside the taglibro repo so config/$env.json\n'
      'can be discovered. See cli/README.md.',
    );
  }

  static CliConfig? _fromEnv(String env, Map<String, String> envMap) {
    final url = envMap['SUPABASE_URL'];
    final key = envMap['SUPABASE_ANON_KEY'];
    if (url == null || url.isEmpty || key == null || key.isEmpty) return null;
    return CliConfig(supabaseUrl: url, anonKey: key, env: env);
  }

  static CliConfig? _fromRepoConfig(String env, String? startDir) {
    final repoRoot = _findRepoRoot(startDir ?? Directory.current.absolute.path);
    if (repoRoot == null) return null;
    final file = File(p.join(repoRoot, 'config', '$env.json'));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final url = json['SUPABASE_URL'] as String?;
    final key = json['SUPABASE_ANON_KEY'] as String?;
    if (url == null || key == null) return null;
    return CliConfig(supabaseUrl: url, anonKey: key, env: env);
  }

  /// Walk up from [startDir] looking for the Flutter package root —
  /// the pubspec whose `name:` is exactly `taglibro`. Required: must
  /// match the root, NOT the sibling `taglibro_cli` (running the CLI
  /// from `cli/` would otherwise stop one level too early).
  static String? _findRepoRoot(String startDir) {
    final exact = RegExp(r'^name:\s*taglibro\s*$', multiLine: true);
    var dir = startDir;
    for (var i = 0; i < 8; i++) {
      final pubspec = File(p.join(dir, 'pubspec.yaml'));
      if (pubspec.existsSync() && exact.hasMatch(pubspec.readAsStringSync())) {
        return dir;
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
    return null;
  }
}
