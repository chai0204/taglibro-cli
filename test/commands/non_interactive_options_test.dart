// Pin the non-interactive option surface so scripted use of the CLI
// stays stable across releases. These tests check that the args are
// declared and parseable; runtime behaviour (read body from stdin,
// skip empty-body confirm, etc.) is exercised end-to-end by the
// smoke tests.
//
// Phase 3.5: non-interactive options for new / edit / login.

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/commands/edit_command.dart';
import 'package:taglibro_cli/src/commands/login_command.dart';
import 'package:taglibro_cli/src/commands/new_command.dart';

void main() {
  CommandRunner<int> buildRunner() {
    final r = CommandRunner<int>('taglibro', 'test runner');
    r.argParser.addOption('env', defaultsTo: 'prod');
    r.argParser.addFlag('json', negatable: false);
    r.addCommand(NewCommand());
    r.addCommand(EditCommand());
    r.addCommand(LoginCommand());
    return r;
  }

  group('new / edit non-interactive options', () {
    test('new exposes --body, --body-stdin, --yes, --non-interactive', () {
      final r = buildRunner();
      final cmd = r.commands['new']!;
      final opts = cmd.argParser.options;
      expect(opts.containsKey('body'), isTrue,
          reason: '--body <markdown> lets scripts pass the diary content');
      expect(opts.containsKey('body-stdin'), isTrue,
          reason: '--body-stdin reads markdown from stdin');
      expect(opts.containsKey('yes'), isTrue,
          reason: '--yes auto-confirms the empty-body abort prompt');
      expect(opts.containsKey('non-interactive'), isTrue,
          reason: '--non-interactive fails fast on any prompt');
    });

    test('edit exposes the same body-source flags', () {
      final r = buildRunner();
      final cmd = r.commands['edit']!;
      final opts = cmd.argParser.options;
      expect(opts.containsKey('body'), isTrue);
      expect(opts.containsKey('body-stdin'), isTrue);
      expect(opts.containsKey('yes'), isTrue);
      expect(opts.containsKey('non-interactive'), isTrue);
    });

    test('--help works without crashing for both', () async {
      final r = buildRunner();
      await r.run(['new', '--help']);
      await r.run(['edit', '--help']);
    });
  });

  group('login non-interactive options', () {
    test('login exposes --email, --password-stdin, --non-interactive', () {
      final r = buildRunner();
      final cmd = r.commands['login']!;
      final opts = cmd.argParser.options;
      expect(opts.containsKey('email'), isTrue);
      expect(opts.containsKey('password-stdin'), isTrue,
          reason: '--password-stdin reads the password from stdin so '
              'scripts never put it on the command line');
      expect(opts.containsKey('non-interactive'), isTrue,
          reason: '--non-interactive errors if email/password not provided '
              'instead of prompting');
    });
  });
}
