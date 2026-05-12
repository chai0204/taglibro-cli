import 'dart:io';

import 'package:path/path.dart' as p;

/// Result of editing a buffer with the user's `$EDITOR`.
class EditOutcome {
  final String content;
  final bool changed;
  final int exitCode;
  const EditOutcome({
    required this.content,
    required this.changed,
    required this.exitCode,
  });
}

class EditorInvoker {
  /// Picks the user's editor by trying:
  ///   1. the `EDITOR` env var
  ///   2. the `VISUAL` env var
  ///   3. a fallback ladder: nano → vim → vi
  /// Returns null when none of those are on `PATH`.
  static String? resolveEditor() {
    for (final candidate in [
      Platform.environment['EDITOR'],
      Platform.environment['VISUAL'],
    ]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    for (final fallback in const ['nano', 'vim', 'vi']) {
      if (_hasOnPath(fallback)) return fallback;
    }
    return null;
  }

  /// Opens [seed] in `$EDITOR` and returns the buffer after the
  /// editor exits. The temp file's name carries [hint] so a user
  /// who looks at /tmp can tell what they were editing.
  ///
  /// We inherit stdio (`Process.start` + `inheritStdio`) so the
  /// editor has direct access to the terminal — `Process.run`
  /// would buffer the editor's output and most TUI editors refuse
  /// to start without a TTY. Hence this is async; the commands
  /// that use it are already Future-returning.
  static Future<EditOutcome> openInEditor({
    required String seed,
    String hint = 'taglibro',
  }) async {
    final editor = resolveEditor();
    if (editor == null) {
      throw StateError(
        'No editor found. Set \$EDITOR (or install nano / vim).',
      );
    }
    final tmp = File(p.join(
      Directory.systemTemp.path,
      '$hint-${DateTime.now().millisecondsSinceEpoch}.md',
    ));
    tmp.writeAsStringSync(seed);
    try {
      // Go through the shell so editors invoked with arguments
      // ("emacs -nw", "code --wait") parse correctly.
      final shell = Platform.environment['SHELL'] ?? '/bin/sh';
      final proc = await Process.start(
        shell,
        ['-c', '$editor "${tmp.path}"'],
        mode: ProcessStartMode.inheritStdio,
      );
      final code = await proc.exitCode;
      final after = tmp.readAsStringSync();
      return EditOutcome(
        content: after,
        changed: after != seed,
        exitCode: code,
      );
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {
        // Editor crashed and left a lock; the user can find it.
      }
    }
  }

  static bool _hasOnPath(String bin) {
    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      if (File(p.join(dir, bin)).existsSync()) return true;
    }
    return false;
  }
}
