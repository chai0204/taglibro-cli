import 'dart:io';

import 'package:args/command_runner.dart';

import '../util/config_store.dart';
import '../util/date_parser.dart';
import '../util/editor_invoker.dart';

/// `tgl date-config` — manage the persisted date-format
/// preference used by `tgl upload` (filename parsing).
class DateConfigCommand extends Command<int> {
  @override
  final name = 'date-config';
  @override
  final description = 'Show or change how filenames are parsed for dates '
      '(`upload` command). Settings live in '
      '~/.config/taglibro/config.json (or %APPDATA% on Windows).';

  DateConfigCommand() {
    addSubcommand(_DateConfigShow());
    addSubcommand(_DateConfigSet());
    addSubcommand(_DateConfigEdit());
  }
}

class _DateConfigShow extends Command<int> {
  @override
  final name = 'show';
  @override
  final description = 'Print the current date_format preference.';

  @override
  Future<int> run() async {
    final store = const ConfigStore();
    final pref = store.loadDateFormat();
    final source = store.exists() ? store.resolvePath() : '(defaults)';
    stdout.writeln('date_format:');
    stdout.writeln('  order:     ${DateFormatPref.formatOrder(pref.order)}');
    stdout.writeln(
      '  separator: ${DateFormatPref.formatSeparator(pref.separator)}',
    );
    stdout.writeln('source: $source');
    if (DateFormatPref.isFilenameUnsafe(pref.separator)) {
      stderr.writeln(
        'note: "${pref.separator}" is a filename-unsafe separator '
        '(reserved on Windows / used as a path separator), so filename '
        'parsing during `tgl upload` will not match real files. '
        'Use `--date` or pass content via stdin in that case.',
      );
    }
    return 0;
  }
}

class _DateConfigSet extends Command<int> {
  @override
  final name = 'set';
  @override
  final description = 'Update one or both of order / separator. '
      'Either flag can be omitted to keep the current value.';

  _DateConfigSet() {
    argParser
      ..addOption('order', help: 'ymd | dmy | mdy')
      ..addOption('separator', help: '- | / | . | _ | : | none');
  }

  @override
  Future<int> run() async {
    final orderRaw = argResults!['order'] as String?;
    final sepRaw = argResults!['separator'] as String?;
    if (orderRaw == null && sepRaw == null) {
      stderr.writeln(
        'Nothing to update — pass --order and/or --separator.',
      );
      return 1;
    }
    final store = const ConfigStore();
    final current = store.loadDateFormat();
    final next = current.copyWith(
      order: orderRaw == null ? null : DateFormatPref.parseOrder(orderRaw),
      separator: sepRaw == null ? null : DateFormatPref.parseSeparator(sepRaw),
    );
    store.saveDateFormat(next);
    stdout.writeln(
      'Updated ${store.resolvePath()}: order=${DateFormatPref.formatOrder(next.order)}, '
      'separator=${DateFormatPref.formatSeparator(next.separator)}',
    );
    if (DateFormatPref.isFilenameUnsafe(next.separator)) {
      stderr.writeln(
        'Warning: "${next.separator}" cannot appear inside a real filename '
        'on every OS — filename parsing during `tgl upload` will not '
        'match files. Use `--date YYYY-MM-DD` for explicit dates.',
      );
    }
    return 0;
  }
}

class _DateConfigEdit extends Command<int> {
  @override
  final name = 'edit';
  @override
  final description = 'Open the config file in \$EDITOR.';

  @override
  Future<int> run() async {
    final store = const ConfigStore();
    final path = store.resolvePath();
    // Make sure the file exists before invoking the editor so the
    // user sees the current shape rather than an empty buffer that
    // would later be parsed as defaults.
    if (!store.exists()) {
      store.saveDateFormat(const DateFormatPref());
    }
    final seed = File(path).readAsStringSync();
    final EditOutcome outcome;
    try {
      outcome = await EditorInvoker.openInEditor(
        seed: seed,
        hint: 'taglibro-config',
      );
    } on StateError catch (e) {
      stderr.writeln(e.message);
      return 5;
    }
    if (outcome.exitCode != 0) {
      stderr.writeln('Editor exited with code ${outcome.exitCode}; '
          'aborting without saving.');
      return 1;
    }
    if (!outcome.changed) {
      stdout.writeln('No changes.');
      return 0;
    }
    // Write the edited content back atomically and round-trip-parse
    // it so a typo (`order: yymd`) surfaces here instead of breaking
    // the next `upload`.
    File('$path.tmp').writeAsStringSync(outcome.content, flush: true);
    if (Platform.isWindows) {
      final existing = File(path);
      if (existing.existsSync()) existing.deleteSync();
    }
    File('$path.tmp').renameSync(path);
    try {
      store.loadDateFormat();
    } catch (e) {
      stderr.writeln('Saved, but the new config did not parse: $e');
      return 1;
    }
    stdout.writeln('Updated $path');
    return 0;
  }
}
