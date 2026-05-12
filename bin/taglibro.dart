import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:taglibro_cli/src/commands/edit_command.dart';
import 'package:taglibro_cli/src/commands/export_command.dart';
import 'package:taglibro_cli/src/commands/list_command.dart';
import 'package:taglibro_cli/src/commands/login_command.dart';
import 'package:taglibro_cli/src/commands/logout_command.dart';
import 'package:taglibro_cli/src/commands/new_command.dart';
import 'package:taglibro_cli/src/commands/rm_command.dart';
import 'package:taglibro_cli/src/commands/search_command.dart';
import 'package:taglibro_cli/src/commands/show_command.dart';
import 'package:taglibro_cli/src/commands/whoami_command.dart';

const _version = '0.1.0';

Future<void> main(List<String> args) async {
  // Phase A intentionally surfaces only auth-related commands.
  // list / show / new / edit / rm / search / export land in later
  // phases (see ../README.md).
  final runner = CommandRunner<int>(
    'taglibro',
    'Terminal client for taglibro.',
  );

  runner.argParser.addOption(
    'env',
    allowed: ['prod', 'dev'],
    defaultsTo: 'prod',
    help: 'Which Supabase environment to talk to.',
  );
  runner.argParser.addFlag(
    'json',
    negatable: false,
    help: 'Emit machine-readable JSON instead of the default '
        'human-readable layout. Honoured by list / show / search.',
  );
  runner.argParser.addFlag(
    'version',
    negatable: false,
    help: 'Print the CLI version and exit.',
  );

  // Auth (Phase A).
  runner.addCommand(LoginCommand());
  runner.addCommand(LogoutCommand());
  runner.addCommand(WhoamiCommand());

  // Read-only diary commands (Phase B).
  runner.addCommand(ListCommand());
  runner.addCommand(ShowCommand());
  runner.addCommand(SearchCommand());
  runner.addCommand(ExportCommand());

  // Write commands (Phase C).
  runner.addCommand(NewCommand());
  runner.addCommand(EditCommand());
  runner.addCommand(RmCommand());

  // Intercept --version before CommandRunner complains about a
  // missing subcommand.
  if (args.contains('--version')) {
    stdout.writeln('taglibro $_version');
    exit(0);
  }

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(1);
  } catch (e, st) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(st);
    exit(99);
  }
}
