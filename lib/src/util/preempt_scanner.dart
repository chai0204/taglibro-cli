import 'dart:io';

import 'package:supabase/supabase.dart';

import '../data/diary_repo.dart';
import 'date_arg.dart';
import 'last_write_store.dart';

/// Compares every record in [store] against the server's current
/// `diaries.updated_at` and writes a stderr warning for any row whose
/// timestamp has moved past what the CLI last wrote.
///
/// Phase 5e: the CLI is stateless between invocations, so it relies
/// on [LastWriteStore] as its memory of "rows I touched". A drift
/// means another client (Flutter app, sibling device, another CLI
/// session) wrote to the same row after the CLI did. The user sees
/// `! 2026-05-14 was modified by another client after your write` and
/// can investigate; the reported entry is then dropped from the
/// store so subsequent commands don't keep nagging.
///
/// Best-effort by design — network errors / a missing row simply
/// skip that entry. A real failure mode here would mean the user
/// can't run *any* CLI command on a flaky network, which is worse
/// than a missed warning.
Future<void> scanAndReportPreempts({
  required SupabaseClient client,
  required String userId,
  LastWriteStore? store,
  IOSink? sink,
}) async {
  final s = store ?? const LastWriteStore();
  final out = sink ?? stderr;
  final records = s.load();
  if (records.isEmpty) return;

  final repo = DiaryRepo(client, userId);
  final survivors = <LastWriteRecord>[];
  for (final r in records) {
    try {
      final current = await repo.fetchUpdatedAt(r.diaryId);
      if (current == null) {
        // Row deleted somewhere else — drop from store, don't warn
        // (the rm/list bug Option 2 path already covers the tombstone
        // notification path).
        continue;
      }
      if (current.isAfter(r.updatedAt)) {
        out.writeln(
          '! ${formatCliDate(r.diaryDate)} was modified by another client '
          'after your write (server: ${current.toUtc().toIso8601String()}; '
          'your write: ${r.updatedAt.toUtc().toIso8601String()}).',
        );
        // Drop reported entry so we don't nag on every subsequent
        // command. If the user re-edits the same diary the new write
        // re-records a fresh record with the latest updated_at.
        continue;
      }
      survivors.add(r);
    } catch (_) {
      // Skip on network / RLS error. The next command retries.
      survivors.add(r);
    }
  }
  s.replaceAll(survivors);
}
