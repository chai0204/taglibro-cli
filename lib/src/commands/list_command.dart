import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';

class ListCommand extends Command<int> {
  @override
  final name = 'list';
  @override
  final description = 'List your own diaries, newest first.';

  ListCommand() {
    argParser
      ..addOption('from', help: 'Earliest date to include (YYYY-MM-DD).')
      ..addOption('to', help: 'Latest date to include (YYYY-MM-DD).')
      ..addOption('limit',
          defaultsTo: '20', help: 'Maximum number of diaries to print.');
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final asJson = (globalResults?['json'] as bool?) ?? false;

    final fromArg = argResults!['from'] as String?;
    final toArg = argResults!['to'] as String?;
    final from =
        fromArg == null ? null : parseCliDate(fromArg, argName: '--from');
    final to = toArg == null ? null : parseCliDate(toArg, argName: '--to');
    final limit = int.tryParse(argResults!['limit'] as String? ?? '20');
    if (limit == null || limit <= 0) {
      stderr.writeln('--limit must be a positive integer.');
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final rows = await DiaryRepo(client, userId).listOwn(
          from: from,
          to: to,
          limit: limit,
        );

        if (asJson) {
          stdout.writeln(jsonEncode(rows.map(_jsonRow).toList()));
          return 0;
        }

        if (rows.isEmpty) {
          stderr.writeln('(no diaries match)');
          return 0;
        }

        for (final row in rows) {
          stdout.writeln(_humanRow(row));
        }
        return 0;
      },
    );
  }

  static Map<String, dynamic> _jsonRow(Map<String, dynamic> r) => {
        'id': r['id'],
        'date': r['date'],
        // Phase 26-4: scope_max_reach replaces the dropped
        // visibility column. Same semantic — effective scope — just
        // sourced from the trigger-computed value.
        'visibility': r['scope_max_reach'],
        'char_count': r['char_count'],
        'preview': _preview(r['body'] as String? ?? ''),
      };

  /// Right-aligns the char count so the preview column lines up
  /// across rows. Visibility column is padded to the widest value
  /// the schema allows ("connected").
  static String _humanRow(Map<String, dynamic> r) {
    final date = r['date'] as String;
    final vis = (r['scope_max_reach'] as String? ?? '').padRight(9);
    final count = (r['char_count'] as num? ?? 0).toString().padLeft(5);
    final preview = _preview(r['body'] as String? ?? '');
    return '$date  $vis  $count 文字  $preview';
  }

  static String _preview(String body) {
    // Collapse whitespace + headings so the row stays single-line.
    final flat = body
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return flat.length > 30 ? '${flat.substring(0, 30)}…' : flat;
  }
}
