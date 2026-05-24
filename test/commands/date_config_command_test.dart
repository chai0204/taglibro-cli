// Phase 27-3: surface tests for `taglibro date-config`. We don't
// touch the real config file — ConfigStore round-trip already has
// dedicated tests in util/config_store_test.dart. Here we just pin
// that the subcommands exist and the flag declarations don't change
// silently.

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/commands/date_config_command.dart';

void main() {
  CommandRunner<int> buildRunner() {
    final r = CommandRunner<int>('taglibro', 'test runner');
    r.argParser.addOption('env', defaultsTo: 'prod');
    r.addCommand(DateConfigCommand());
    return r;
  }

  group('date-config command surface', () {
    test('exposes the three subcommands', () {
      final r = buildRunner();
      final cmd = r.commands['date-config']!;
      final subs = cmd.subcommands.keys.toSet();
      expect(subs, containsAll(['show', 'set', 'edit']));
    });

    test('`set` exposes --order and --separator', () {
      final r = buildRunner();
      final set = r.commands['date-config']!.subcommands['set']!;
      expect(set.argParser.options.containsKey('order'), isTrue);
      expect(set.argParser.options.containsKey('separator'), isTrue);
    });

    test('`set` with no flags exits 1', () async {
      final r = buildRunner();
      final code = await r.run(['date-config', 'set']);
      expect(code, 1);
    });

    test('--help works for the parent and each subcommand', () async {
      final r = buildRunner();
      await r.run(['date-config', '--help']);
      await r.run(['date-config', 'show', '--help']);
      await r.run(['date-config', 'set', '--help']);
      await r.run(['date-config', 'edit', '--help']);
    });
  });
}
