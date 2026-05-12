import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/date_arg.dart';

void main() {
  group('parseCliDate', () {
    test('parses a canonical YYYY-MM-DD into UTC midnight', () {
      final d = parseCliDate('2026-05-12');
      expect(d.year, 2026);
      expect(d.month, 5);
      expect(d.day, 12);
      expect(d.isUtc, isTrue);
      expect(d.hour, 0);
    });

    test('rejects malformed input with UsageException → exit 1', () {
      expect(
        () => parseCliDate('bad-date'),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects partial dates', () {
      expect(() => parseCliDate('2026-5-12'), throwsA(isA<UsageException>()));
      expect(() => parseCliDate('2026-05'), throwsA(isA<UsageException>()));
      expect(() => parseCliDate('05-12-2026'), throwsA(isA<UsageException>()));
    });

    test('rejects out-of-range months / days', () {
      // DateTime.utc throws for out-of-range; the parser maps that
      // to UsageException so the user sees a clean error.
      expect(
        () => parseCliDate('2026-13-01'),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => parseCliDate('2026-02-30'),
        throwsA(isA<UsageException>()),
      );
    });

    test('formatCliDate slices the ISO string', () {
      expect(formatCliDate(DateTime.utc(2026, 1, 5)), '2026-01-05');
      expect(formatCliDate(DateTime.utc(2026, 12, 31)), '2026-12-31');
    });
  });
}
