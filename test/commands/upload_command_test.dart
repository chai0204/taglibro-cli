// Phase 27-3: surface-level tests for `taglibro upload`. End-to-end
// upload behaviour (real Supabase round-trip) is covered by
// tools/smoke_e2e.sh; here we just pin the flag set, mutex rules, and
// usage-error exit codes so script consumers see a stable contract.

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/commands/upload_command.dart';

void main() {
  CommandRunner<int> buildRunner() {
    final r = CommandRunner<int>('taglibro', 'test runner');
    r.argParser.addOption('env', defaultsTo: 'prod');
    r.addCommand(UploadCommand());
    return r;
  }

  group('upload command surface', () {
    test('exposes the documented flag set', () {
      final r = buildRunner();
      final cmd = r.commands['upload']!;
      final opts = cmd.argParser.options;
      for (final flag in [
        'date',
        'date-order',
        'date-separator',
        'append',
        'overwrite',
        'yes',
        'non-interactive',
      ]) {
        expect(opts.containsKey(flag), isTrue,
            reason: '$flag should be a recognised upload flag');
      }
    });

    test('--help runs without crashing', () async {
      final r = buildRunner();
      final code = await r.run(['upload', '--help']);
      expect(code, anyOf(0, isNull));
    });

    test('--append and --overwrite are mutually exclusive (exit 1)', () async {
      final r = buildRunner();
      final code = await r.run([
        'upload',
        '--append',
        '--overwrite',
        '/nonexistent/file.md',
      ]);
      expect(code, 1);
    });

    test('no files + no --date + no stdin available → exit 2', () async {
      // stdin is a TTY in the test runner; readLineSync would block,
      // but we short-circuit before reading because no --date was set.
      final r = buildRunner();
      final code = await r.run(['upload']);
      expect(code, 2);
    });

    test('--date with multiple files → exit 1 (data-loss guard)', () async {
      final r = buildRunner();
      final code = await r.run([
        'upload',
        '--date',
        '2026-05-24',
        '/tmp/a.md',
        '/tmp/b.md',
      ]);
      expect(code, 1);
    });

    test('--date-separator rejects unsupported values via UsageException',
        () async {
      final r = buildRunner();
      expect(
        () => r.run(['upload', '--date-separator', '|', '/tmp/a.md']),
        throwsA(isA<UsageException>()),
      );
    });

    test('--date-order rejects unsupported values via UsageException',
        () async {
      final r = buildRunner();
      // args package's `allowed` validation throws UsageException
      // before our code runs — the throw still proves the constraint.
      expect(
        () => r.run(['upload', '--date-order', 'yyyy', '/tmp/a.md']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
