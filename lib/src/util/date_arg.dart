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
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  try {
    final d = DateTime.utc(year, month, day);
    // DateTime.utc silently rolls over out-of-range components
    // (`DateTime.utc(2026, 13, 1)` → 2027-01-01). Reject any input
    // whose components don't round-trip, so '2026-13-01' /
    // '2026-02-30' surface as usage errors instead of being
    // quietly accepted.
    if (d.year != year || d.month != month || d.day != day) {
      throw const FormatException('date components out of range');
    }
    return d;
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
