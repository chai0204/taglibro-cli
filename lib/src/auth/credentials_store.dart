import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persisted session + Supabase target for the CLI.
///
/// Saved to `~/.config/taglibro/credentials.json` (or
/// `$XDG_CONFIG_HOME/taglibro/credentials.json` when set), with
/// mode 0600 so other users on shared boxes can't read the
/// `refresh_token`.
class StoredCredentials {
  final String supabaseUrl;
  final String anonKey;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String? email;

  const StoredCredentials({
    required this.supabaseUrl,
    required this.anonKey,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    this.email,
  });

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'supabase_url': supabaseUrl,
        'anon_key': anonKey,
        'session': {
          'access_token': accessToken,
          'refresh_token': refreshToken,
          'expires_at': expiresAt.toUtc().toIso8601String(),
        },
        'user': {
          'id': userId,
          if (email != null) 'email': email,
        },
      };

  static StoredCredentials fromJson(Map<String, dynamic> json) {
    final session = json['session'] as Map<String, dynamic>;
    final user = json['user'] as Map<String, dynamic>;
    return StoredCredentials(
      supabaseUrl: json['supabase_url'] as String,
      anonKey: json['anon_key'] as String,
      accessToken: session['access_token'] as String,
      refreshToken: session['refresh_token'] as String,
      expiresAt: DateTime.parse(session['expires_at'] as String),
      userId: user['id'] as String,
      email: user['email'] as String?,
    );
  }

  StoredCredentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) =>
      StoredCredentials(
        supabaseUrl: supabaseUrl,
        anonKey: anonKey,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
        userId: userId,
        email: email,
      );
}

class CredentialsStore {
  /// Override the default location — used by tests, and by callers
  /// who want to keep dry-run / smoke runs out of the real config
  /// dir.
  final String? overridePath;

  const CredentialsStore({this.overridePath});

  /// Resolves to `$XDG_CONFIG_HOME/taglibro/credentials.json` when
  /// set, otherwise `~/.config/taglibro/credentials.json`.
  String resolvePath() {
    if (overridePath != null) return overridePath!;
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(_homeDir(), '.config');
    return p.join(base, 'taglibro', 'credentials.json');
  }

  bool exists() => File(resolvePath()).existsSync();

  /// Returns null when no credentials are saved.
  StoredCredentials? load() {
    final file = File(resolvePath());
    if (!file.existsSync()) return null;
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return StoredCredentials.fromJson(json);
  }

  /// Atomically write [creds] to disk with mode 0600. We write to a
  /// temp file first so a crash mid-write can't corrupt the existing
  /// credentials (chmod-then-rename is the standard pattern).
  void save(StoredCredentials creds) {
    final path = resolvePath();
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(creds.toJson()),
      flush: true,
    );

    // chmod 600 on the temp file *before* the rename so the final
    // path never appears with a more permissive mode, even briefly.
    // dart:io has no chmod helper; shell out to /bin/chmod.
    Process.runSync('chmod', ['600', tmp.path]);
    tmp.renameSync(path);
  }

  /// Best-effort delete. No-op if the file is already gone.
  void delete() {
    final file = File(resolvePath());
    if (file.existsSync()) file.deleteSync();
  }

  static String _homeDir() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'HOME is not set; cannot locate ~/.config for credentials.',
      );
    }
    return home;
  }
}
