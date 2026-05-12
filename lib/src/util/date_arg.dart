import 'package:args/command_runner.dart';

/// Strict `YYYY-MM-DD` parser. CLI commands accept dates only in
/// that canonical form to avoid locale-dependent surprises.
///
/// Throws [UsageException] (caught by CommandRunner → exit 1) when
/// the input doesn't match the format, so the user sees a clean
/// "Invalid date" message instead of a stack trace.
DateTime parseCliDate(String input, {String? argName}) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(input);
  if (m == null) {
    throw UsageException(
      'Invalid date "$input"${argName == null ? "" : " for $argName"} — '
      'expected YYYY-MM-DD.',
      'taglibro --help',
    );
  }
  try {
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  } catch (_) {
    throw UsageException(
      'Invalid date "$input"${argName == null ? "" : " for $argName"}.',
      'taglibro --help',
    );
  }
}

/// Canonical wire format used for both PostgREST filters and
/// human-readable output. We slice the ISO string rather than
/// formatting by hand to avoid pulling intl into the CLI bundle.
String formatCliDate(DateTime d) => d.toIso8601String().substring(0, 10);
