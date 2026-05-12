import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:supabase/supabase.dart';

import '../auth/credentials_store.dart';

class LogoutCommand extends Command<int> {
  @override
  final name = 'logout';
  @override
  final description =
      'Forget the local session. Best-effort server-side logout '
      'first, then deletes ~/.config/taglibro/credentials.json.';

  @override
  Future<int> run() async {
    // Logout doesn't need ConfigResolver — the URL / anon key are
    // already inside the stored credentials, and if there's no file
    // there's nothing to log out of.
    final store = const CredentialsStore();
    final creds = store.load();
    if (creds == null) {
      stdout.writeln('Not logged in — nothing to do.');
      return 0;
    }

    try {
      final client = SupabaseClient(creds.supabaseUrl, creds.anonKey);
      await client.auth.setSession(creds.refreshToken);
      await client.auth.signOut();
    } catch (_) {
      // Network down / refresh dead — local delete still runs.
    }
    store.delete();
    stdout.writeln('✓ Logged out. Removed ${store.resolvePath()}');
    return 0;
  }
}
