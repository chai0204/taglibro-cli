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

  /// Resolves the credentials file path.
  ///
  /// - POSIX (Linux/macOS): `$XDG_CONFIG_HOME/taglibro/credentials.json`
  ///   when set, otherwise `$HOME/.config/taglibro/credentials.json`.
  /// - Windows: `%APPDATA%\taglibro\credentials.json`. APPDATA already
  ///   resolves to a per-user roaming directory that no other Windows
  ///   user can read by default, which is why we don't apply an ACL
  ///   tightening pass (which would be `icacls` shelling and is hard
  ///   to get right cross-version).
  String resolvePath() {
    if (overridePath != null) return overridePath!;
    return resolveDefaultPath(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
  }

  /// Pure resolver — separated so unit tests can drive both branches
  /// without needing to actually run on Windows.
  static String resolveDefaultPath({
    required bool isWindows,
    required Map<String, String> environment,
  }) {
    if (isWindows) {
      final appData = environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError(
          'APPDATA is not set; cannot locate the credentials file. '
          'This is normally set automatically by Windows — if you see '
          'this from a non-interactive shell, set APPDATA explicitly.',
        );
      }
      return p.join(appData, 'taglibro', 'credentials.json');
    }
    final xdg = environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return p.join(xdg, 'taglibro', 'credentials.json');
    }
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'HOME is not set; cannot locate ~/.config for credentials.',
      );
    }
    return p.join(home, '.config', 'taglibro', 'credentials.json');
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

  /// Atomically write [creds] to disk.
  ///
  /// POSIX: chmod 600 on the temp file *before* the rename so the final
  /// path never appears with a more permissive mode, even briefly.
  /// dart:io has no chmod helper, so we shell out to /bin/chmod.
  ///
  /// Windows: the file lives under %APPDATA%\taglibro\, which is
  /// per-user roaming storage that other users on the same machine
  /// can't read by default — no extra ACL pass needed. (Setting NTFS
  /// ACLs from Dart would mean shelling to icacls.exe with quoting
  /// pitfalls, and the per-user directory already gives us the same
  /// guarantee POSIX 0600 does on a shared box.)
  void save(StoredCredentials creds) {
    final path = resolvePath();
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(creds.toJson()),
      flush: true,
    );

    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', tmp.path]);
    }
    // File.renameSync replaces the destination on POSIX but throws on
    // Windows if the target already exists. Delete first there.
    if (Platform.isWindows) {
      final existing = File(path);
      if (existing.existsSync()) existing.deleteSync();
    }
    tmp.renameSync(path);
  }

  /// Best-effort delete. No-op if the file is already gone.
  void delete() {
    final file = File(resolvePath());
    if (file.existsSync()) file.deleteSync();
  }
}
