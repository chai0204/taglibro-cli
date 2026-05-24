// Phase 27-1: pure unit tests for the date-parser used by
// `taglibro upload`. No I/O, no Supabase — exercise the rules in
// ~/life/works/taglibro/cli-file-upload-spec.md directly.

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/date_parser.dart';

void main() {
  group('DateFormatPref', () {
    test('defaults to ymd / "-"', () {
      const p = DateFormatPref();
      expect(p.order, DateOrder.ymd);
      expect(p.separator, '-');
    });

    test('parseOrder accepts the three supported values', () {
      expect(DateFormatPref.parseOrder('ymd'), DateOrder.ymd);
      expect(DateFormatPref.parseOrder('dmy'), DateOrder.dmy);
      expect(DateFormatPref.parseOrder('mdy'), DateOrder.mdy);
    });

    test('parseOrder rejects unknown values via UsageException', () {
      expect(
        () => DateFormatPref.parseOrder('yyyy'),
        throwsA(isA<UsageException>()),
      );
    });

    test('parseSeparator maps "none" to compact ""', () {
      expect(DateFormatPref.parseSeparator('none'), '');
      expect(DateFormatPref.parseSeparator(''), '');
      expect(DateFormatPref.parseSeparator('-'), '-');
      expect(DateFormatPref.parseSeparator('/'), '/');
      expect(DateFormatPref.parseSeparator('.'), '.');
      expect(DateFormatPref.parseSeparator('_'), '_');
      expect(DateFormatPref.parseSeparator(':'), ':');
    });

    test('parseSeparator rejects unsupported characters', () {
      expect(
        () => DateFormatPref.parseSeparator('|'),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => DateFormatPref.parseSeparator(' '),
        throwsA(isA<UsageException>()),
      );
    });

    test('isFilenameUnsafe flags `/` and `:`', () {
      expect(DateFormatPref.isFilenameUnsafe('/'), isTrue);
      expect(DateFormatPref.isFilenameUnsafe(':'), isTrue);
      expect(DateFormatPref.isFilenameUnsafe('-'), isFalse);
      expect(DateFormatPref.isFilenameUnsafe('.'), isFalse);
      expect(DateFormatPref.isFilenameUnsafe('_'), isFalse);
      expect(DateFormatPref.isFilenameUnsafe(''), isFalse);
    });
  });

  group('parseFromArg', () {
    test('parses canonical YYYY-MM-DD into UTC midnight', () {
      final d = parseFromArg('2023-05-24');
      expect(d.year, 2023);
      expect(d.month, 5);
      expect(d.day, 24);
      expect(d.isUtc, isTrue);
      expect(d.hour, 0);
    });

    test('rejects malformed input', () {
      expect(() => parseFromArg('bad-date'), throwsA(isA<UsageException>()));
      expect(() => parseFromArg('2023-5-24'), throwsA(isA<UsageException>()));
    });

    test('rejects out-of-range components', () {
      expect(() => parseFromArg('2023-13-01'), throwsA(isA<UsageException>()));
      expect(() => parseFromArg('2023-02-30'), throwsA(isA<UsageException>()));
    });
  });

  group('parseFromFilename — ymd', () {
    test('hyphen separator, leading match', () {
      final d = parseFromFilename(
        '2023-05-24.md',
        order: DateOrder.ymd,
        separator: '-',
      );
      expect(d, DateTime.utc(2023, 5, 24));
    });

    test('hyphen separator with surrounding prefix/suffix', () {
      expect(
        parseFromFilename(
          'journal-2023-05-24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
      expect(
        parseFromFilename(
          'pre-2023-05-24-post.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
      expect(
        parseFromFilename(
          '2023-05-24-foo.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });

    test('dot separator (regex-escape sanity)', () {
      expect(
        parseFromFilename(
          '2023.05.24.md',
          order: DateOrder.ymd,
          separator: '.',
        ),
        DateTime.utc(2023, 5, 24),
      );
      // hyphen-separator setting must NOT match dot-separator input.
      expect(
        parseFromFilename(
          '2023.05.24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
    });

    test('underscore separator', () {
      expect(
        parseFromFilename(
          'diary_2023_05_24.md',
          order: DateOrder.ymd,
          separator: '_',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });

    test('colon separator (regex meta-char must be escape-safe)', () {
      expect(
        parseFromFilename(
          '2023:05:24.md',
          order: DateOrder.ymd,
          separator: ':',
        ),
        DateTime.utc(2023, 5, 24),
      );
      // hyphen-separator setting must NOT match colon-separator input.
      expect(
        parseFromFilename(
          '2023:05:24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
    });

    test('forward-slash separator is filename-unsafe — basename eats it', () {
      // `/` is a directory separator on POSIX, so `path.basename`
      // strips everything before the last `/`. That means `/` cannot
      // appear *inside* a filename — it always ends up split into
      // directory + base. The parser returns null and the upload
      // command surfaces the filename-unsafe warning to the user.
      expect(
        parseFromFilename(
          '2023/05/24.md',
          order: DateOrder.ymd,
          separator: '/',
        ),
        isNull,
      );
      // The setting itself is still valid — it's intended for `--date`
      // / stdin invocations, not for filename parsing.
      expect(DateFormatPref.isFilenameUnsafe('/'), isTrue);
    });

    test('compact (empty separator) takes 8 consecutive digits', () {
      expect(
        parseFromFilename(
          '20230524.md',
          order: DateOrder.ymd,
          separator: '',
        ),
        DateTime.utc(2023, 5, 24),
      );
      expect(
        parseFromFilename(
          'note-20230524-foo.md',
          order: DateOrder.ymd,
          separator: '',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });

    test('compact prefers the first match when multiple dates appear', () {
      expect(
        parseFromFilename(
          '2023052420260101.md',
          order: DateOrder.ymd,
          separator: '',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });
  });

  group('parseFromFilename — dmy', () {
    test('hyphen separator', () {
      expect(
        parseFromFilename(
          '24-05-2023-notes.md',
          order: DateOrder.dmy,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });

    test('compact', () {
      expect(
        parseFromFilename(
          '日記_24052023.md',
          order: DateOrder.dmy,
          separator: '',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });
  });

  group('parseFromFilename — mdy', () {
    test('hyphen separator', () {
      expect(
        parseFromFilename(
          '05-24-2023.md',
          order: DateOrder.mdy,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });

    test('compact', () {
      expect(
        parseFromFilename(
          '05242023-foo.md',
          order: DateOrder.mdy,
          separator: '',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });
  });

  group('parseFromFilename — failures', () {
    test('returns null when no date is present', () {
      expect(
        parseFromFilename(
          '日記.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
    });

    test('returns null when components are out-of-range', () {
      expect(
        parseFromFilename(
          '2099-13-32.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
      expect(
        parseFromFilename(
          '2023-02-30.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
    });

    test('does not accept single-digit month/day even with surrounding text',
        () {
      // 2-digit padding is mandatory: '2023-5-24' must not match.
      expect(
        parseFromFilename(
          '2023-5-24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        isNull,
      );
    });

    test('basename behaviour — directory separators are stripped', () {
      // path is treated as basename; the `/` in the path should not be
      // confused with a date separator setting.
      expect(
        parseFromFilename(
          'subdir/2023-05-24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
      expect(
        parseFromFilename(
          r'C:\Users\foo\2023-05-24.md',
          order: DateOrder.ymd,
          separator: '-',
        ),
        DateTime.utc(2023, 5, 24),
      );
    });
  });
}
