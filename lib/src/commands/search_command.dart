import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../util/cli_run.dart';

class SearchCommand extends Command<int> {
  @override
  final name = 'search';
  @override
  final description =
      'Full-text search across your own diaries (ILIKE). Calls the '
      'search_diary_blocks RPC and filters results to your user id.';

  SearchCommand() {
    argParser.addOption('limit',
        defaultsTo: '20',
        help: 'Maximum number of matching blocks to return.');
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final asJson = (globalResults?['json'] as bool?) ?? false;

    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: tgl search "<query>"');
      return 1;
    }
    final query = positional.join(' ').trim();
    if (query.isEmpty) {
      stderr.writeln('Search query is empty.');
      return 1;
    }
    final limit = int.tryParse(argResults!['limit'] as String? ?? '20');
    if (limit == null || limit <= 0) {
      stderr.writeln('--limit must be a positive integer.');
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final hits = await DiaryRepo(client, userId).searchOwn(
          query,
          limit: limit,
        );

        if (asJson) {
          stdout.writeln(jsonEncode(hits));
          return 0;
        }

        if (hits.isEmpty) {
          stderr.writeln('(no matches)');
          return 0;
        }

        for (final hit in hits) {
          final date = hit['diary_date'] as String;
          final snippet = _snippet(hit['block_content'] as String? ?? '',
              query: query);
          stdout.writeln('$date  $snippet');
        }
        return 0;
      },
    );
  }

  /// Build a single-line excerpt around the first occurrence of
  /// [query], with ~30 chars of context either side. Falls back to
  /// the head of the block when [query] doesn't ILIKE the block (it
  /// shouldn't, since the RPC only returns matches — but the
  /// fallback keeps the renderer total).
  static String _snippet(String body, {required String query}) {
    final lower = body.toLowerCase();
    final idx = lower.indexOf(query.toLowerCase());
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (idx < 0) {
      return flat.length > 60 ? '${flat.substring(0, 60)}…' : flat;
    }
    final start = (idx - 20).clamp(0, body.length);
    final end = (idx + query.length + 30).clamp(0, body.length);
    var seg = body
        .substring(start, end)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (start > 0) seg = '…$seg';
    if (end < body.length) seg = '$seg…';
    return seg;
  }
}
