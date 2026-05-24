import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../data/diary_repo.dart';
import '../markdown/block_scope.dart';
import '../util/cli_run.dart';
import '../util/config_store.dart';
import '../util/date_parser.dart';
import '../util/last_write_store.dart';
import '../util/prompt.dart';

/// `taglibro upload` — bulk-upload one or more markdown files into
/// the user's diaries, with the date for each file resolved by the
/// `--date > filename > today` priority described in
/// ~/life/works/taglibro/cli-file-upload-spec.md §3.
///
/// Conflicts with an existing diary for the same date fall back to a
/// confirm prompt by default; `--append` and `--overwrite` short-
/// circuit the prompt for scripted use.
class UploadCommand extends Command<int> {
  @override
  final name = 'upload';
  @override
  final description = 'Upload one or more markdown files as diaries. '
      'Date for each file: --date > filename match > today. '
      'See `taglibro date-config` for filename parsing settings.';

  UploadCommand() {
    argParser
      ..addOption(
        'date',
        help: 'Diary date (YYYY-MM-DD). Applies to every file — only allowed '
            'with a single file or stdin.',
      )
      ..addOption(
        'date-order',
        allowed: ['ymd', 'dmy', 'mdy'],
        help: 'Override the persisted date order for filename parsing.',
      )
      ..addOption(
        'date-separator',
        help: 'Override the persisted separator for filename parsing '
            '(-, /, ., _, :, none). Only affects this invocation.',
      )
      ..addFlag(
        'append',
        negatable: false,
        help: 'When a diary already exists for the target date, append '
            'the new content after a blank line instead of prompting.',
      )
      ..addFlag(
        'overwrite',
        negatable: false,
        help: 'When a diary already exists for the target date, replace '
            'it instead of prompting. Destructive — use --yes for fully '
            'unattended runs.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Auto-confirm prompts (default-yes for conflict resolution).',
      )
      ..addFlag(
        'non-interactive',
        negatable: false,
        help: 'Error out instead of prompting. Implies --yes for any '
            'default-yes prompts.',
      );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';

    final append = argResults!['append'] as bool;
    final overwrite = argResults!['overwrite'] as bool;
    if (append && overwrite) {
      stderr.writeln('--append and --overwrite are mutually exclusive.');
      return 1;
    }

    final yes = argResults!['yes'] as bool;
    final nonInteractive = argResults!['non-interactive'] as bool;

    // Resolve format pref: persisted defaults, then per-flag override.
    final store = const ConfigStore();
    var pref = store.loadDateFormat();
    final orderRaw = argResults!['date-order'] as String?;
    final sepRaw = argResults!['date-separator'] as String?;
    if (orderRaw != null) {
      pref = pref.copyWith(order: DateFormatPref.parseOrder(orderRaw));
    }
    if (sepRaw != null) {
      pref = pref.copyWith(separator: DateFormatPref.parseSeparator(sepRaw));
    }
    if (DateFormatPref.isFilenameUnsafe(pref.separator)) {
      stderr.writeln(
        'note: separator "${pref.separator}" cannot appear inside real '
        'filenames on every OS; filename parsing will not match. Pass '
        '--date YYYY-MM-DD or use stdin in that case.',
      );
    }

    final files = argResults!.rest;
    final explicitDateArg = argResults!['date'] as String?;

    if (files.isEmpty) {
      // stdin path: only valid with --date (no filename to parse).
      if (explicitDateArg == null) {
        stderr.writeln(
          'No files given. Pipe content into stdin and pass --date YYYY-MM-DD '
          'to upload a single diary from stdin, or list files as arguments.',
        );
        return 2;
      }
      final body = _readAllStdin();
      if (body.trim().isEmpty) {
        stderr.writeln('stdin was empty — nothing to upload.');
        return 1;
      }
      final date = parseFromArg(explicitDateArg);
      return runWithSignedInClient(
        env: env,
        body: (client, userId) => _uploadOne(
          client: client,
          userId: userId,
          source: '<stdin>',
          date: date,
          content: body,
          append: append,
          overwrite: overwrite,
          yes: yes,
          nonInteractive: nonInteractive,
        ),
      );
    }

    if (explicitDateArg != null && files.length > 1) {
      stderr.writeln(
        '--date can only be used with a single file or stdin '
        '(otherwise every file would overwrite the same date).',
      );
      return 1;
    }

    return runWithSignedInClient(
      env: env,
      body: (client, userId) async {
        var failed = 0;
        for (var i = 0; i < files.length; i++) {
          final path = files[i];
          final prefix = '[${i + 1}/${files.length}] $path';
          final file = File(path);
          if (!file.existsSync()) {
            stderr.writeln('$prefix → file not found');
            failed++;
            continue;
          }
          final content = file.readAsStringSync();

          // Date decision per file.
          final DateTime date;
          String dateNote = '';
          if (explicitDateArg != null) {
            date = parseFromArg(explicitDateArg);
          } else {
            final fromName = parseFromFilename(
              path,
              order: pref.order,
              separator: pref.separator,
            );
            if (fromName != null) {
              date = fromName;
            } else {
              date = _todayUtc();
              dateNote = ' (no date in filename, using today)';
            }
          }

          stdout.write('$prefix → ${formatDate(date)}$dateNote → ');
          final code = await _uploadOne(
            client: client,
            userId: userId,
            source: p.basename(path),
            date: date,
            content: content,
            append: append,
            overwrite: overwrite,
            yes: yes,
            nonInteractive: nonInteractive,
            inlineProgress: true,
          );
          if (code != 0) failed++;
        }
        final ok = files.length - failed;
        stdout.writeln('Done. $ok/${files.length} uploaded successfully.');
        return failed == 0 ? 0 : 1;
      },
    );
  }

  /// Resolve the conflict policy + write a single diary. Returns the
  /// CLI exit-code contribution for this file.
  ///
  /// When [inlineProgress] is true the caller has already written the
  /// `[i/N] path → date → ` prefix on stdout; this method appends the
  /// result word (created / updated / skipped / failed) + newline.
  Future<int> _uploadOne({
    required dynamic client,
    required String userId,
    required String source,
    required DateTime date,
    required String content,
    required bool append,
    required bool overwrite,
    required bool yes,
    required bool nonInteractive,
    bool inlineProgress = false,
  }) async {
    final repo = DiaryRepo(client, userId);
    final existing = await repo.findOwnByDate(date);

    String finalContent = content;
    String resultWord = 'created';

    if (existing != null) {
      final ConflictResolution decision = _resolveConflict(
        date: date,
        append: append,
        overwrite: overwrite,
        yes: yes,
        nonInteractive: nonInteractive,
      );
      switch (decision) {
        case ConflictResolution.abort:
          _emitInline(inlineProgress, 'skipped (existing diary, abort)');
          return 1;
        case ConflictResolution.append:
          final existingMd = (existing['raw_markdown'] as String?) ??
              (existing['content'] as String?) ??
              '';
          finalContent = existingMd.trimRight() + '\n\n' + content;
          resultWord = 'appended';
          break;
        case ConflictResolution.overwrite:
          resultWord = 'overwritten';
          break;
      }
    }

    try {
      // Phase 26-4: baseScope is no longer a real scope decision —
      // server-side compute derives it from profiles.default_visibility.
      // We pass 'private' to match `taglibro new` so the literal in
      // tag-less blocks stays consistent across commands.
      final blocks = parseTaggedMarkdown(finalContent, baseScope: 'private');
      final result = await repo.saveDiary(
        date: date,
        rawMarkdown: finalContent,
        blocks: blocks,
      );
      try {
        const LastWriteStore().append(LastWriteRecord(
          diaryId: result.diaryId,
          updatedAt: result.updatedAt,
          diaryDate: date,
        ));
      } catch (_) {}

      _emitInline(
        inlineProgress,
        '$resultWord (${result.blockCount} blocks, ${finalContent.runes.length} chars)',
      );
      return 0;
    } catch (e) {
      _emitInline(inlineProgress, 'failed: $e');
      return 1;
    }
  }

  ConflictResolution _resolveConflict({
    required DateTime date,
    required bool append,
    required bool overwrite,
    required bool yes,
    required bool nonInteractive,
  }) {
    if (append) return ConflictResolution.append;
    if (overwrite) return ConflictResolution.overwrite;
    if (nonInteractive) {
      stderr.writeln(
        '\n${formatDate(date)} の日記は既に存在します。'
        '--non-interactive モードでは --append / --overwrite が必須です。',
      );
      return ConflictResolution.abort;
    }
    if (yes) return ConflictResolution.append;
    // Interactive: default to append so a typo doesn't drop existing
    // content. The user can pass --overwrite explicitly when they want
    // to replace.
    final go = confirm(
      '\n${formatDate(date)} の日記が既にあります。末尾に追加しますか? '
      '(No で skip。上書きしたい場合は --overwrite を指定して再実行)',
      defaultYes: true,
    );
    return go ? ConflictResolution.append : ConflictResolution.abort;
  }

  static void _emitInline(bool inlineProgress, String word) {
    if (inlineProgress) {
      stdout.writeln(word);
    } else {
      stdout.writeln('→ $word');
    }
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

  static DateTime _todayUtc() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// `YYYY-MM-DD` slice of an ISO timestamp. Kept private rather than
  /// importing `date_arg.dart` again so the command stays focused.
  static String formatDate(DateTime d) => d.toIso8601String().substring(0, 10);
}

enum ConflictResolution {
  append,
  overwrite,
  abort,
}
