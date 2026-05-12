import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';

class ExportCommand extends Command<int> {
  @override
  final name = 'export';
  @override
  final description =
      'Export your own diaries between --from and --to as a single '
      'Markdown document. Scope-tagged fences are preserved verbatim '
      'so a round-trip back into the editor stays lossless.';

  ExportCommand() {
    argParser
      ..addOption('from',
          help: 'Earliest date to include (YYYY-MM-DD), inclusive.')
      ..addOption('to',
          help: 'Latest date to include (YYYY-MM-DD), inclusive.')
      ..addOption('output',
          abbr: 'o',
          help: 'Path to write to. Required unless --stdout is set.')
      ..addFlag('stdout',
          negatable: false, help: 'Write the export to stdout instead of a file.');
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';

    final fromArg = argResults!['from'] as String?;
    final toArg = argResults!['to'] as String?;
    if (fromArg == null || toArg == null) {
      stderr.writeln('Both --from and --to are required.');
      return 1;
    }
    final from = parseCliDate(fromArg, argName: '--from');
    final to = parseCliDate(toArg, argName: '--to');
    if (to.isBefore(from)) {
      stderr.writeln('--to must not be earlier than --from.');
      return 1;
    }

    final outputPath = argResults!['output'] as String?;
    final toStdout = argResults!['stdout'] as bool;
    if (outputPath == null && !toStdout) {
      stderr.writeln('Specify either --output <path> or --stdout.');
      return 1;
    }
    if (outputPath != null && toStdout) {
      stderr.writeln('--output and --stdout are mutually exclusive.');
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final repo = DiaryRepo(client, userId);

        // Collect everything first so we can report a count + write
        // a single file atomically. PostgREST caps a single response
        // at 1000 rows, so the repo streams in pages of 500.
        final diaries = <Map<String, dynamic>>[];
        await for (final row
            in repo.streamForExport(from: from, to: to, pageSize: 500)) {
          diaries.add(row);
        }

        // Stream came back newest-first; flip so the exported doc
        // reads chronologically.
        diaries.sort((a, b) =>
            (a['date'] as String).compareTo(b['date'] as String));

        final body = _render(diaries);

        if (toStdout) {
          stdout.write(body);
          return 0;
        }
        final f = File(outputPath!);
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(body);
        stdout.writeln(
            '✓ ${diaries.length} 件の日記を ${f.path} に書き出しました');
        return 0;
      },
    );
  }

  static String _render(List<Map<String, dynamic>> diaries) {
    final buf = StringBuffer();
    for (var i = 0; i < diaries.length; i++) {
      final d = diaries[i];
      buf.writeln('# ${d['date']}');
      buf.writeln();
      final body = (d['raw_markdown'] as String?) ??
          (d['content'] as String?) ??
          '';
      buf.write(body);
      if (!body.endsWith('\n')) buf.writeln();
      if (i < diaries.length - 1) {
        buf.writeln();
        buf.writeln('---');
        buf.writeln();
      }
    }
    return buf.toString();
  }
}
