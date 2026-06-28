import 'dart:io';

import 'package:args/command_runner.dart';

import '../auth/credentials_store.dart';

class WhoamiCommand extends Command<int> {
  @override
  final name = 'whoami';
  @override
  final description =
      'Print the email of the currently signed-in user. Does not '
      'hit the network — reads the locally saved session.';

  @override
  Future<int> run() async {
    // Deliberately skips AuthService / ConfigResolver: whoami should
    // work without any Supabase config on disk, since the answer
    // lives entirely inside ~/.config/taglibro/credentials.json.
    final creds = const CredentialsStore().load();
    if (creds == null) {
      stderr.writeln('Not logged in. Run `tgl login` first.');
      return 2; // exit code per design.md §5
    }

    stdout.writeln(creds.email ?? '(unknown email — user id ${creds.userId})');
    return 0;
  }
}
