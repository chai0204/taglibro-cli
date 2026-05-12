import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:supabase/supabase.dart';

import '../auth/auth_service.dart';

class LoginCommand extends Command<int> {
  @override
  final name = 'login';
  @override
  final description =
      'Sign in with email + password. Saves the session to '
      '~/.config/taglibro/credentials.json (mode 0600).';

  LoginCommand() {
    argParser.addOption(
      'email',
      abbr: 'e',
      help: 'Email to log in with. Prompted interactively if omitted.',
    );
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Re-login even if a session already exists.',
    );
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Walk the prompts but do not contact Supabase or save '
          'credentials. Used by smoke checks.',
    );
  }

  @override
  Future<int> run() async {
    final env = (globalResults?['env'] as String?) ?? 'prod';
    final auth = AuthService.forEnv(env: env);

    if (!(argResults!['force'] as bool) && auth.store.exists()) {
      final existing = auth.store.load();
      stderr.writeln(
        'Already logged in as ${existing?.email ?? "(unknown)"}. '
        'Pass --force to re-login.',
      );
      return 0;
    }

    final email = (argResults!['email'] as String?) ??
        _prompt('Email: ', echo: true);
    if (email.isEmpty) {
      stderr.writeln('Email is required.');
      return 1;
    }
    final password = _prompt('Password: ', echo: false);
    if (password.isEmpty) {
      stderr.writeln('Password is required.');
      return 1;
    }

    if (argResults!['dry-run'] as bool) {
      stdout.writeln(
        '[dry-run] would sign in to ${auth.config.supabaseUrl} as $email; '
        'no network call, no credentials written.',
      );
      return 0;
    }

    try {
      final confirmedEmail =
          await auth.loginWithPassword(email: email, password: password);
      stdout.writeln('✓ Logged in as $confirmedEmail');
      stdout.writeln('  Saved credentials to ${auth.store.resolvePath()}');
      return 0;
    } on AuthException catch (e) {
      stderr.writeln('Login failed: ${e.message}');
      return 1;
    } on AuthFailure catch (e) {
      stderr.writeln('Login failed: ${e.message}');
      return 1;
    } catch (e) {
      stderr.writeln('Unexpected error during login: $e');
      return 99;
    }
  }

  /// Read a line from stdin. When [echo] is false the typed
  /// characters aren't echoed to the terminal — used for passwords.
  ///
  /// `stdin.echoMode` only works on a real TTY. When stdin is a
  /// pipe / heredoc (CI, smoke tests) the toggle throws
  /// `StdinException: Inappropriate ioctl for device`. We detect
  /// that with `stdin.hasTerminal` and skip the toggle — the typed
  /// chars just aren't masked in the non-interactive path, which is
  /// fine because that's not a security-sensitive context anyway.
  static String _prompt(String label, {required bool echo}) {
    stdout.write(label);
    final tty = stdin.hasTerminal;
    final wasEcho = (tty && !echo) ? stdin.echoMode : true;
    if (tty && !echo) stdin.echoMode = false;
    try {
      final line = stdin.readLineSync();
      if (!echo) stdout.writeln();
      return (line ?? '').trim();
    } finally {
      if (tty && !echo) stdin.echoMode = wasEcho;
    }
  }
}
