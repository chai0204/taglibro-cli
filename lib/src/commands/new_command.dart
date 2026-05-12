import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../markdown/block_scope.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';
import '../util/editor_invoker.dart';
import '../util/prompt.dart';
import 'edit_command.dart';

const _allowedVisibility = ['private', 'public', 'connected'];

class NewCommand extends Command<int> {
  @override
  final name = 'new';
  @override
  final description =
      'Create a new diary for --date (default: today). Opens \$EDITOR '
      'on an empty buffer, then upserts the diary and its blocks.';

  NewCommand() {
    argParser
      ..addOption('date', help: 'Diary date (YYYY-MM-DD). Defaults to today.')
      ..addOption(
        'visibility',
        defaultsTo: 'private',
        allowed: _allowedVisibility,
        help: 'Default diary visibility (public / connected / private).',
      );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final visibility = argResults!['visibility'] as String;
    final dateArg = argResults!['date'] as String?;
    final date = dateArg == null
        ? _today()
        : parseCliDate(dateArg, argName: '--date');

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final repo = DiaryRepo(client, userId);
        final existing = await repo.findOwnByDate(date);
        if (existing != null) {
          final go = confirm(
            '${formatCliDate(date)} の日記は既に存在します。'
            'edit に切り替えますか?',
          );
          if (!go) return 1;
          return EditCommand.runForDate(
            client: client,
            userId: userId,
            date: date,
          );
        }

        final EditOutcome outcome;
        try {
          outcome = await EditorInvoker.openInEditor(
            seed: '',
            hint: 'taglibro-new-${formatCliDate(date)}',
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
        if (outcome.content.trim().isEmpty) {
          // design.md §7.2-5: confirm before silently dropping.
          final abort = confirm(
            '本文が空です。中止しますか?',
            defaultYes: true,
          );
          if (abort) {
            stderr.writeln('aborted');
            return 1;
          }
        }

        final blocks =
            parseTaggedMarkdown(outcome.content, baseScope: visibility);
        final result = await repo.saveDiary(
          date: date,
          rawMarkdown: outcome.content,
          visibility: visibility,
          blocks: blocks,
        );
        stdout.writeln(
          '✓ ${formatCliDate(date)} の日記を作成しました '
          '(${outcome.content.runes.length} 文字, ${result.blockCount} ブロック)',
        );
        return 0;
      },
    );
  }

  static DateTime _today() {
    // Local-date wallclock matches what the Flutter editor uses for
    // "今日". We store as UTC midnight for the same-day equivalence
    // the unique constraint expects.
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }
}
