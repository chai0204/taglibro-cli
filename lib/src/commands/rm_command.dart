import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';
import '../util/prompt.dart';

class RmCommand extends Command<int> {
  @override
  final name = 'rm';
  @override
  final description = 'Delete one of your diaries by date '
      '(cascades to blocks / reactions / notifications).';

  RmCommand() {
    argParser.addFlag(
      'yes',
      negatable: false,
      help: 'Skip the confirmation prompt.',
    );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final skipConfirm = argResults!['yes'] as bool;

    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: tgl rm YYYY-MM-DD [--yes]');
      return 1;
    }
    final date = parseCliDate(positional.first);

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final repo = DiaryRepo(client, userId);

        // Confirm before we touch the network — design.md §5 makes
        // rm a confirmation-by-default action. --yes opts out for
        // scripts.
        if (!skipConfirm) {
          final go = confirm(
            '${formatCliDate(date)} の日記を削除します。よろしいですか?',
          );
          if (!go) {
            stderr.writeln('aborted');
            return 1;
          }
        }

        final deleted = await repo.deleteOwnByDate(date);
        if (!deleted) {
          stderr.writeln(
              '${formatCliDate(date)} の日記が存在しません。');
          return 4;
        }
        stdout.writeln('✓ ${formatCliDate(date)} の日記を削除しました');
        return 0;
      },
    );
  }
}
