import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/diary_repo.dart';
import '../markdown/block_scope.dart';
import '../util/cli_run.dart';
import '../util/date_arg.dart';
import '../util/editor_invoker.dart';
import '../util/last_write_store.dart';
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
        help: 'Deprecated since Phase 26-4: diary scope is now driven '
            'entirely by your profile\'s default_visibility (Settings → '
            'デフォルト公開範囲 in the web app). Argument is still parsed '
            'for backward compatibility but ignored — set the default '
            'in Settings instead.',
      )
      ..addOption(
        'body',
        help: 'Diary body markdown. Skips \$EDITOR; use this for scripted '
            'writes. Mutually exclusive with --body-stdin.',
      )
      ..addFlag(
        'body-stdin',
        negatable: false,
        help: 'Read the diary body from stdin. Skips \$EDITOR. Useful for '
            "piping (e.g. \`echo '# title' | tgl new --body-stdin\`).",
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Auto-confirm prompts (empty body, etc.) — needed for fully '
            'unattended runs.',
      )
      ..addFlag(
        'non-interactive',
        negatable: false,
        help: 'Error out instead of prompting when input is missing. '
            'Implies --yes for default-yes prompts.',
      );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    // Phase 26-4: --visibility is deprecated. Emit a one-line stderr
    // notice when the user explicitly set it (not just defaulted),
    // but proceed — the server-side trigger sources scope from
    // profiles.default_visibility regardless.
    if (argResults!.wasParsed('visibility')) {
      stderr.writeln(
        'Warning: --visibility is deprecated since Phase 26-4 and is '
        'now ignored. Set your default in the web app '
        '(Settings → デフォルト公開範囲) instead.',
      );
    }
    final dateArg = argResults!['date'] as String?;
    final date =
        dateArg == null ? _today() : parseCliDate(dateArg, argName: '--date');

    final bodyArg = argResults!['body'] as String?;
    final bodyStdin = argResults!['body-stdin'] as bool;
    final yes = argResults!['yes'] as bool;
    final nonInteractive = argResults!['non-interactive'] as bool;

    if (bodyArg != null && bodyStdin) {
      stderr.writeln('--body and --body-stdin are mutually exclusive.');
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        final repo = DiaryRepo(client, userId);
        final existing = await repo.findOwnByDate(date);
        if (existing != null) {
          if (nonInteractive) {
            stderr.writeln(
              '${formatCliDate(date)} の日記は既に存在します。'
              '--non-interactive モードでは edit に自動切替しません。'
              '`tgl edit ${formatCliDate(date)}` を直接呼んでください。',
            );
            return 1;
          }
          final go = yes ||
              confirm(
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

        final String content;
        final int editorExitCode;
        if (bodyArg != null) {
          content = bodyArg;
          editorExitCode = 0;
        } else if (bodyStdin) {
          content = _readAllStdin();
          editorExitCode = 0;
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
              seed: '',
              hint: 'taglibro-new-${formatCliDate(date)}',
            );
          } on StateError catch (e) {
            stderr.writeln(e.message);
            return 5;
          }
          content = outcome.content;
          editorExitCode = outcome.exitCode;
        }

        if (editorExitCode != 0) {
          stderr.writeln('Editor exited with code $editorExitCode; '
              'aborting without saving.');
          return 1;
        }
        if (content.trim().isEmpty) {
          // design.md §7.2-5: confirm before silently dropping.
          if (nonInteractive || !yes) {
            if (nonInteractive) {
              stderr.writeln('本文が空です。中止します。');
              return 1;
            }
            final abort = confirm(
              '本文が空です。中止しますか?',
              defaultYes: true,
            );
            if (abort) {
              stderr.writeln('aborted');
              return 1;
            }
          }
        }

        // Phase 26-4: parseTaggedMarkdown still wants a baseScope so
        // the leading "no tags" block gets a default — pass 'private'
        // unconditionally. The actual diary scope is computed
        // server-side from profiles.default_visibility plus tag
        // widening, so the literal here only affects which block
        // gets the `#private` shape when no tag is present.
        final blocks = parseTaggedMarkdown(content, baseScope: 'private');
        final result = await repo.saveDiary(
          date: date,
          rawMarkdown: content,
          blocks: blocks,
        );
        // Phase 5e: record so the next CLI command can detect a
        // preempt — i.e. somebody else writing to the same row after
        // this. Best-effort; a disk error here shouldn't fail the
        // user's save.
        try {
          const LastWriteStore().append(LastWriteRecord(
            diaryId: result.diaryId,
            updatedAt: result.updatedAt,
            diaryDate: date,
          ));
        } catch (_) {}
        stdout.writeln(
          '✓ ${formatCliDate(date)} の日記を作成しました '
          '(${content.runes.length} 文字, ${result.blockCount} ブロック)',
        );
        return 0;
      },
    );
  }

  /// Drain stdin into a single string. Used by --body-stdin so the
  /// caller can pipe a multi-line markdown buffer in.
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

  static DateTime _today() {
    // Local-date wallclock matches what the Flutter editor uses for
    // "今日". We store as UTC midnight for the same-day equivalence
    // the unique constraint expects.
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }
}
