import 'dart:io';

import 'package:supabase/supabase.dart';

import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';
import 'preempt_scanner.dart';

/// Runs [body] with a freshly-authenticated [SupabaseClient] and the
/// signed-in user id. Centralises the AuthFailure → exit-code
/// mapping defined in design.md §5 so every command surfaces the
/// same codes for the same conditions.
///
/// Exit codes returned by this helper:
///   - 2: `notLoggedIn` — no credentials file
///   - 3: `sessionExpired` — refresh rejected
///   - 5: `serverError` — network / unexpected from refresh
///
/// Before [body] runs, [scanAndReportPreempts] checks every entry in
/// the LastWriteStore against the server's current `updated_at` and
/// writes a stderr warning for anything that moved. The scan is
/// best-effort — a network error during the check doesn't block
/// command execution.
Future<int> runWithSignedInClient({
  required String env,
  required Future<int> Function(SupabaseClient client, String userId) body,
}) async {
  final auth = AuthService.forEnv(env: env);
  late final SupabaseClient client;
  late final String userId;
  try {
    client = await auth.signedInClient();
    final creds = const CredentialsStore().load();
    userId = creds!.userId;
  } on AuthFailure catch (e) {
    stderr.writeln(e.message);
    return switch (e.kind) {
      AuthFailureKind.notLoggedIn => 2,
      AuthFailureKind.sessionExpired => 3,
      AuthFailureKind.serverError => 5,
    };
  }

  // Phase 5e: opportunistic preempt scan. Skipped silently when the
  // LastWriteStore is empty (cold path — common for `list`, `whoami`,
  // etc. that don't follow a write).
  try {
    await scanAndReportPreempts(client: client, userId: userId);
  } catch (_) {
    // Don't let the scan throw past this point — it's a UX nicety,
    // not a correctness gate.
  }

  try {
    return await body(client, userId);
  } on PostgrestException catch (e) {
    stderr.writeln('Server error: ${e.message}');
    return 5;
  } on AuthException catch (e) {
    stderr.writeln('Auth error: ${e.message}');
    return 5;
  } catch (e) {
    stderr.writeln('Unexpected error: $e');
    return 99;
  }
}
