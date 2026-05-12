import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:supabase/supabase.dart';

import '../data/diary_repo.dart';
import '../markdown/block_scope.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';
import '../util/editor_invoker.dart';

class EditCommand extends Command<int> {
  @override
  final name = 'edit';
  @override
  final description = "Open an existing diary in \$EDITOR and upsert "
      "the result. Exits 4 when the date doesn't exist.";

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';

    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: taglibro edit YYYY-MM-DD');
      return 1;
    }
    final date = parseCliDate(positional.first);

    return runWithSignedInClient(
      env: env,
      body: (client, userId) => runForDate(
        client: client,
        userId: userId,
        date: date,
      ),
    );
  }

  /// Edit body shared with `new --date <existing>` so the dispatch
  /// from there reuses the diff / EDITOR / save logic verbatim.
  static Future<int> runForDate({
    required SupabaseClient client,
    required String userId,
    required DateTime date,
  }) async {
    final repo = DiaryRepo(client, userId);
    final diary = await repo.findOwnByDate(date);
    if (diary == null) {
      stderr.writeln(
        '${formatCliDate(date)} の日記が存在しません。'
        '`taglibro new --date ${formatCliDate(date)}` で作成してください。',
      );
      return 4;
    }

    final seed = (diary['raw_markdown'] as String?) ??
        (diary['content'] as String?) ??
        '';
    final visibility = (diary['visibility'] as String?) ?? 'private';

    final EditOutcome outcome;
    try {
      outcome = await EditorInvoker.openInEditor(
        seed: seed,
        hint: 'taglibro-edit-${formatCliDate(date)}',
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
      stdout.writeln('変更なし、何もしません。');
      return 0;
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
      '✓ ${formatCliDate(date)} の日記を更新しました '
      '(${outcome.content.runes.length} 文字, ${result.blockCount} ブロック)',
    );
    return 0;
  }
}
