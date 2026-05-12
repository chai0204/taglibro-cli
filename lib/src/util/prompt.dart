import 'dart:io';

/// Single-line yes/no prompt. [defaultYes] controls which key the
/// blank-Enter falls through to and the casing of the `[Y/n]` hint.
///
/// Returns `defaultYes` when stdin isn't a TTY (CI / pipeline mode)
/// so a missing answer doesn't hang the build. Callers that need to
/// hard-fail without a TTY should gate with `stdin.hasTerminal`
/// before calling.
bool confirm(String question, {bool defaultYes = false}) {
  final hint = defaultYes ? '[Y/n]' : '[y/N]';
  stdout.write('$question $hint ');
  if (!stdin.hasTerminal) {
    stdout.writeln(defaultYes ? 'y' : 'n');
    return defaultYes;
  }
  final raw = stdin.readLineSync()?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return defaultYes;
  return raw == 'y' || raw == 'yes';
}
