import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'date_arg.dart';

/// Order of year / month / day in a filename. Spec:
/// ~/life/works/taglibro/cli-file-upload-spec.md §2.
enum DateOrder {
  ymd,
  dmy,
  mdy,
}

/// User preference for how dates are written in filenames the CLI is
/// asked to upload. Persisted to `config.json`; `--date-order` /
/// `--date-separator` override at invocation time.
class DateFormatPref {
  final DateOrder order;
  final String separator;

  const DateFormatPref({
    this.order = DateOrder.ymd,
    this.separator = '-',
  });

  DateFormatPref copyWith({DateOrder? order, String? separator}) =>
      DateFormatPref(
        order: order ?? this.order,
        separator: separator ?? this.separator,
      );

  /// Map a CLI string to [DateOrder], throwing [UsageException] on
  /// unknown values so CommandRunner surfaces a clean error.
  static DateOrder parseOrder(String raw) {
    switch (raw) {
      case 'ymd':
        return DateOrder.ymd;
      case 'dmy':
        return DateOrder.dmy;
      case 'mdy':
        return DateOrder.mdy;
      default:
        throw UsageException(
          'Invalid date order "$raw" — expected ymd / dmy / mdy.',
          'taglibro upload --help',
        );
    }
  }

  /// Separators that can legally appear in a filename on every
  /// supported OS. `/` is a path separator everywhere; `:` is a
  /// reserved character on Windows (NTFS uses it for alternate data
  /// streams). Both can still be selected — for `--date` / stdin /
  /// `taglibro upload` from non-file sources — but the caller
  /// (`upload_command`) emits a stderr warning so users don't pick
  /// them by accident for filename parsing.
  static const filenameUnsafeSeparators = {'/', ':'};

  /// True when [separator] is one of the unsafe-in-filename chars
  /// above. Returns false for the empty (compact) separator.
  static bool isFilenameUnsafe(String separator) =>
      filenameUnsafeSeparators.contains(separator);

  /// Map a CLI string to the actual separator character. `"none"` and
  /// `""` both mean compact (no separator).
  static String parseSeparator(String raw) {
    if (raw == 'none' || raw == '') return '';
    const allowed = {'-', '/', '.', '_', ':'};
    if (allowed.contains(raw)) return raw;
    throw UsageException(
      'Invalid date separator "$raw" — expected one of -, /, ., _, :, none.',
      'taglibro upload --help',
    );
  }

  /// Inverse of [parseSeparator]; used by `date-config show` to print
  /// the empty separator as the friendlier `"none"` keyword.
  static String formatSeparator(String separator) =>
      separator.isEmpty ? 'none' : separator;

  /// Inverse of [parseOrder]; used by `date-config show` /
  /// serialisation.
  static String formatOrder(DateOrder order) => order.name;
}

/// Parse `--date YYYY-MM-DD`. Thin wrapper around [parseCliDate] so
/// `upload_command` doesn't have to import two date utilities.
DateTime parseFromArg(String input) => parseCliDate(input, argName: '--date');

/// Extract a date from [filename] (or path — directories are stripped
/// via `path.basename`) using the configured [order] + [separator].
///
/// Returns null when the file name doesn't contain a well-formed date.
/// Out-of-range components (`2099-13-32`) also return null instead of
/// silently rolling over, so the caller can pick a fallback policy.
DateTime? parseFromFilename(
  String filename, {
  required DateOrder order,
  required String separator,
}) {
  final base = p.basename(filename.replaceAll(r'\', '/'));
  final pattern = _patternFor(order: order, separator: separator);
  final match = pattern.firstMatch(base);
  if (match == null) return null;

  final int year, month, day;
  switch (order) {
    case DateOrder.ymd:
      year = int.parse(match.group(1)!);
      month = int.parse(match.group(2)!);
      day = int.parse(match.group(3)!);
      break;
    case DateOrder.dmy:
      day = int.parse(match.group(1)!);
      month = int.parse(match.group(2)!);
      year = int.parse(match.group(3)!);
      break;
    case DateOrder.mdy:
      month = int.parse(match.group(1)!);
      day = int.parse(match.group(2)!);
      year = int.parse(match.group(3)!);
      break;
  }

  final d = DateTime.utc(year, month, day);
  // DateTime.utc rolls over invalid components (`DateTime.utc(2099,13,32)`
  // → 2100-02-01). Reject anything that doesn't round-trip so the
  // caller can fall back to --date / today instead of silently storing
  // the wrong date.
  if (d.year != year || d.month != month || d.day != day) return null;
  return d;
}

RegExp _patternFor({
  required DateOrder order,
  required String separator,
}) {
  // Escape the separator so `.` doesn't accidentally match any char.
  final sep = RegExp.escape(separator);
  final y = r'(\d{4})';
  final m = r'(\d{2})';
  final d = r'(\d{2})';
  switch (order) {
    case DateOrder.ymd:
      return RegExp('$y$sep$m$sep$d');
    case DateOrder.dmy:
      return RegExp('$d$sep$m$sep$y');
    case DateOrder.mdy:
      return RegExp('$m$sep$d$sep$y');
  }
}
