import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';

class ShowCommand extends Command<int> {
  @override
  final name = 'show';
  @override
  final description = 'Show one of your diaries by date (YYYY-MM-DD).';

  ShowCommand() {
    argParser.addFlag(
      'blocks',
      negatable: false,
      help: 'Print one section per stored block with its scope label.',
    );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final asJson = (globalResults?['json'] as bool?) ?? false;
    final withBlocks = argResults!['blocks'] as bool;

    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: taglibro show YYYY-MM-DD [--blocks]');
      return 1;
    }
    final date = parseCliDate(positional.first);

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final repo = DiaryRepo(client, userId);
        final diary = await repo.findOwnByDate(date);
        if (diary == null) {
          stderr.writeln('No diary for ${formatCliDate(date)}.');
          return 4; // resource not found, per design.md §5
        }

        List<Map<String, dynamic>>? blocks;
        if (withBlocks || asJson) {
          blocks = await repo.blocksFor(diary['id'] as int);
        }

        if (asJson) {
          stdout.writeln(jsonEncode({
            ...diary,
            'blocks': blocks,
          }));
          return 0;
        }

        if (withBlocks && blocks != null) {
          _renderBlocks(diary, blocks);
        } else {
          _renderRawMarkdown(diary);
        }
        return 0;
      },
    );
  }

  static void _renderRawMarkdown(Map<String, dynamic> diary) {
    final header = '# ${diary['date']}   '
        '[${diary['visibility']}]  '
        '${diary['char_count']} 文字';
    stdout.writeln(header);
    stdout.writeln();
    stdout.writeln(diary['raw_markdown'] as String? ??
        diary['content'] as String? ??
        '');
  }

  static void _renderBlocks(
    Map<String, dynamic> diary,
    List<Map<String, dynamic>> blocks,
  ) {
    stdout.writeln('# ${diary['date']}   [${diary['visibility']}]');
    stdout.writeln();
    if (blocks.isEmpty) {
      // Legacy diary that was created before the per-block split.
      stdout.writeln('(no per-block data — raw_markdown only)');
      stdout.writeln();
      stdout.writeln(diary['raw_markdown'] as String? ??
          diary['content'] as String? ??
          '');
      return;
    }
    for (final b in blocks) {
      final scope = b['original_scope'] as String? ?? 'private';
      final cat = b['category_id'];
      final label = cat == null ? '[$scope]' : '[$scope:$cat]';
      stdout.writeln(label);
      stdout.writeln((b['content'] as String? ?? '').trim());
      stdout.writeln();
    }
  }
}
