import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:supabase/supabase.dart';

import '../data/diary_repo.dart';
import '../markdown/block_scope.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';
import '../util/editor_invoker.dart';
import '../util/last_write_store.dart';

class EditCommand extends Command<int> {
  @override
  final name = 'edit';
  @override
  final description = "Open an existing diary in \$EDITOR and upsert "
      "the result. Exits 4 when the date doesn't exist.";

  EditCommand() {
    argParser
      ..addOption(
        'body',
        help: 'Replace the diary body with the given markdown. Skips '
            '\$EDITOR. Mutually exclusive with --body-stdin.',
      )
      ..addFlag(
        'body-stdin',
        negatable: false,
        help: 'Read the new body from stdin. Skips \$EDITOR.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Auto-confirm prompts (e.g. "no changes detected"). For '
            'non-interactive scripts.',
      )
      ..addFlag(
        'non-interactive',
        negatable: false,
        help: 'Error out instead of prompting. Implies that body must '
            'come from --body or --body-stdin.',
      );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';

    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: taglibro edit YYYY-MM-DD');
      return 1;
    }
    final date = parseCliDate(positional.first);

    final bodyArg = argResults!['body'] as String?;
    final bodyStdin = argResults!['body-stdin'] as bool;
    final nonInteractive = argResults!['non-interactive'] as bool;

    if (bodyArg != null && bodyStdin) {
      stderr.writeln('--body and --body-stdin are mutually exclusive.');
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) => runForDate(
        client: client,
        userId: userId,
        date: date,
        bodyOverride: bodyArg ?? (bodyStdin ? _readAllStdin() : null),
        nonInteractive: nonInteractive,
      ),
    );
  }

  /// Edit body shared with `new --date <existing>` so the dispatch
  /// from there reuses the diff / EDITOR / save logic verbatim.
  ///
  /// [bodyOverride] short-circuits the editor — used by --body /
  /// --body-stdin for scripted writes. [nonInteractive] makes the
  /// "no editor available" / "no changes" paths fail loudly instead
  /// of asking.
  static Future<int> runForDate({
    required SupabaseClient client,
    required String userId,
    required DateTime date,
    String? bodyOverride,
    bool nonInteractive = false,
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

    final String content;
    final bool changed;
    if (bodyOverride != null) {
      content = bodyOverride;
      changed = bodyOverride != seed;
    } else {
      if (nonInteractive) {
        stderr.writeln(
          '--non-interactive モードでは --body / --body-stdin が必須です。',
        );
        return 1;
      }
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
      content = outcome.content;
      changed = outcome.changed;
    }

    if (!changed) {
      stdout.writeln('変更なし、何もしません。');
      return 0;
    }

    final blocks = parseTaggedMarkdown(content, baseScope: visibility);
    final result = await repo.saveDiary(
      date: date,
      rawMarkdown: content,
      visibility: visibility,
      blocks: blocks,
    );
    // Phase 5e: record for the next-command preempt scan.
    try {
      const LastWriteStore().append(LastWriteRecord(
        diaryId: result.diaryId,
        updatedAt: result.updatedAt,
        diaryDate: date,
      ));
    } catch (_) {}
    stdout.writeln(
      '✓ ${formatCliDate(date)} の日記を更新しました '
      '(${content.runes.length} 文字, ${result.blockCount} ブロック)',
    );
    return 0;
  }

  static String _readAllStdin() {
    final buf = StringBuffer();
    String? line;
    while ((line = stdin.readLineSync(encoding: systemEncoding)) != null) {
      buf
        ..write(line)
        ..write('\n');
    }
    return buf.toString();
  }
}
