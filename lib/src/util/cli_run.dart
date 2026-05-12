import 'dart:io';

import 'package:supabase/supabase.dart';

import '../auth/auth_service.dart';
import '../auth/credentials_store.dart';

/// Runs [body] with a freshly-authenticated [SupabaseClient] and the
/// signed-in user id. Centralises the AuthFailure → exit-code
/// mapping defined in design.md §5 so every command surfaces the
/// same codes for the same conditions.
///
/// Exit codes returned by this helper:
///   - 2: `notLoggedIn` — no credentials file
///   - 3: `sessionExpired` — refresh rejected
///   - 5: `serverError` — network / unexpected from refresh
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
