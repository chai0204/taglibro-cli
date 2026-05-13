// Red tests for the upcoming `taglibro category` command family
// (Phase 2 of Task 2). These pin the CLI surface so Phase 3's
// implementation has to satisfy the exact subcommand names,
// help-text contracts, and argument shapes.
//
// Initially: ALL CASES FAIL because no CategoryCommand is wired
// into bin/taglibro.dart yet. Phase 3 makes them green by adding
// the subcommands and an underlying CategoryRepo.

import 'package:args/command_runner.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/commands/category_command.dart';

void main() {
  // The runner is constructed exactly like bin/taglibro.dart's
  // does so the parsed subcommand surface matches production.
  CommandRunner<int> buildRunner() {
    final r = CommandRunner<int>('taglibro', 'test runner');
    r.argParser.addOption('env', defaultsTo: 'prod');
    r.argParser.addFlag('json', negatable: false);
    r.addCommand(CategoryCommand());
    return r;
  }

  group('category command family is wired up', () {
    test('top-level "category" command is registered', () {
      final r = buildRunner();
      expect(r.commands.containsKey('category'), isTrue);
    });

    test('exposes the five expected subcommands', () {
      final r = buildRunner();
      final cat = r.commands['category']!;
      expect(
        cat.subcommands.keys.toSet(),
        {'list', 'add', 'rm', 'assign', 'unassign'},
      );
    });
  });

  group('subcommand argument contracts', () {
    test('list takes no positional args', () async {
      final r = buildRunner();
      // help shouldn't throw — proves the subcommand is callable.
      await r.run(['category', 'list', '--help']);
    });

    test('add takes <name> + optional --color', () {
      final r = buildRunner();
      final add = r.commands['category']!.subcommands['add']!;
      expect(add.argParser.options.containsKey('color'), isTrue);
    });

    test('rm takes <id> + --yes flag', () {
      final r = buildRunner();
      final rm = r.commands['category']!.subcommands['rm']!;
      expect(rm.argParser.options.containsKey('yes'), isTrue);
    });

    test('assign and unassign each take two positionals (cat, user)',
        () async {
      final r = buildRunner();
      // Calling with --help validates the subcommand exists +
      // parses; positional validation lives at runtime.
      await r.run(['category', 'assign', '--help']);
      await r.run(['category', 'unassign', '--help']);
    });
  });
}
