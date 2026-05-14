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
  ///   3. a per-OS fallback ladder
  ///      - POSIX: nano → vim → vi
  ///      - Windows: notepad (always available, ships with the OS)
  /// Returns null when none of those resolve.
  static String? resolveEditor() => resolveEditorFrom(
        environment: Platform.environment,
        isWindows: Platform.isWindows,
        hasOnPath: _hasOnPath,
      );

  /// Pure resolver — separated so unit tests can drive each branch
  /// (env-var hit, OS-specific fallback, no-editor-anywhere) without
  /// depending on what's actually installed on the test host.
  static String? resolveEditorFrom({
    required Map<String, String> environment,
    required bool isWindows,
    required bool Function(String bin) hasOnPath,
  }) {
    for (final candidate in [
      environment['EDITOR'],
      environment['VISUAL'],
    ]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    final ladder = isWindows
        ? const ['notepad.exe', 'notepad']
        : const ['nano', 'vim', 'vi'];
    for (final fallback in ladder) {
      if (hasOnPath(fallback)) return fallback;
    }
    // Windows always ships with notepad.exe — even if it wasn't found
    // on PATH (rare but possible in stripped images), fall back to the
    // bare name and let Process.start hit the system32 copy.
    if (isWindows) return 'notepad.exe';
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
      // ("emacs -nw", "code --wait") parse correctly. Windows uses
      // cmd.exe /c with double-quoted args; POSIX uses sh -c with a
      // single quoted command line.
      final Process proc;
      if (Platform.isWindows) {
        proc = await Process.start(
          'cmd.exe',
          ['/c', editor, tmp.path],
          mode: ProcessStartMode.inheritStdio,
        );
      } else {
        final shell = Platform.environment['SHELL'] ?? '/bin/sh';
        proc = await Process.start(
          shell,
          ['-c', '$editor "${tmp.path}"'],
          mode: ProcessStartMode.inheritStdio,
        );
      }
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
