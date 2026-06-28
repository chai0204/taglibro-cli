import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'date_parser.dart';

/// Top-level settings file for the CLI. Currently only carries the
/// date-format preference used by `tgl upload`; structured as
/// `{ schema_version, date_format: {...} }` so future settings can
/// land next to it without a breaking change.
///
/// Path resolution mirrors [CredentialsStore]: POSIX uses
/// `$XDG_CONFIG_HOME/taglibro/config.json` (or
/// `$HOME/.config/taglibro/config.json` when XDG is unset), Windows
/// uses `%APPDATA%\taglibro\config.json`. The path is intentionally
/// shared with `credentials.json` so a user only has one taglibro
/// directory to back up / wipe.
class ConfigStore {
  final String? overridePath;

  const ConfigStore({this.overridePath});

  String resolvePath() {
    if (overridePath != null) return overridePath!;
    return resolveDefaultPath(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
  }

  static String resolveDefaultPath({
    required bool isWindows,
    required Map<String, String> environment,
  }) {
    if (isWindows) {
      final appData = environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw StateError(
          'APPDATA is not set; cannot locate the config file. This is '
          'normally set automatically by Windows — if you see this from '
          'a non-interactive shell, set APPDATA explicitly.',
        );
      }
      return p.join(appData, 'taglibro', 'config.json');
    }
    final xdg = environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return p.join(xdg, 'taglibro', 'config.json');
    }
    final home = environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError(
        'HOME is not set; cannot locate ~/.config for taglibro config.',
      );
    }
    return p.join(home, '.config', 'taglibro', 'config.json');
  }

  bool exists() => File(resolvePath()).existsSync();

  /// Load the persisted [DateFormatPref], or the defaults when the
  /// file is missing / empty. Malformed JSON throws so the user sees
  /// "your config is broken" instead of silently reverting to ymd-`-`.
  DateFormatPref loadDateFormat() {
    final file = File(resolvePath());
    if (!file.existsSync()) return const DateFormatPref();
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return const DateFormatPref();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final df = json['date_format'];
    if (df is! Map<String, dynamic>) return const DateFormatPref();
    final orderRaw = (df['order'] as String?) ?? 'ymd';
    final sepRaw = (df['separator'] as String?) ?? '-';
    return DateFormatPref(
      order: DateFormatPref.parseOrder(orderRaw),
      separator: DateFormatPref.parseSeparator(
        // `null` in the JSON is treated as the default by the `??`
        // above; an empty string is the explicit "compact" value.
        sepRaw,
      ),
    );
  }

  /// Persist [pref], creating the parent directory + file when
  /// missing. Existing unrelated fields in the JSON are kept verbatim
  /// so future settings co-located in the same file aren't dropped.
  void saveDateFormat(DateFormatPref pref) {
    final path = resolvePath();
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    Map<String, dynamic> current = {};
    final file = File(path);
    if (file.existsSync()) {
      final raw = file.readAsStringSync();
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) current = decoded;
      }
    }
    current['schema_version'] = 1;
    current['date_format'] = {
      'order': DateFormatPref.formatOrder(pref.order),
      'separator': pref.separator,
    };

    // Atomic write so a crash mid-save doesn't leave a half-written
    // config that breaks the next CLI invocation.
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(current),
      flush: true,
    );
    if (Platform.isWindows) {
      final existing = File(path);
      if (existing.existsSync()) existing.deleteSync();
    }
    tmp.renameSync(path);
  }
}
