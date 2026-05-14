import 'package:supabase/supabase.dart';

import '../markdown/block_scope.dart';

/// Thin wrapper around the Supabase queries the read-only commands
/// share. RLS on `diaries` is `auth.uid() = user_id OR visibility =
/// 'public'`, so without an explicit `user_id` filter a `select`
/// also leaks other users' public diaries — we add the filter
/// everywhere we want "my diaries only" semantics.
class DiaryRepo {
  final SupabaseClient _client;
  final String _userId;

  DiaryRepo(this._client, this._userId);

  /// Columns shared by `list` and `show` (the latter additionally
  /// reads raw_markdown / content for the full body).
  static const _summaryCols =
      'id, date, visibility, char_count, body, base_scope, created_at, updated_at';

  /// Newest-first list of own diaries within the optional date
  /// window. PostgREST caps responses at 1000 rows so any larger
  /// [limit] is silently clamped — Phase B export pages through.
  Future<List<Map<String, dynamic>>> listOwn({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) async {
    final base =
        _client.from('diaries').select(_summaryCols).eq('user_id', _userId);
    final filtered =
        _applyDateRange(base, from, to).order('date', ascending: false);
    return await filtered.limit(limit);
  }

  /// Single diary for [date]; returns null when nothing matches.
  /// Uses the (user_id, date) UNIQUE constraint so this is at most
  /// one row.
  Future<Map<String, dynamic>?> findOwnByDate(DateTime date) async {
    final isoDate = date.toIso8601String().substring(0, 10);
    final rows = await _client
        .from('diaries')
        .select(
          '$_summaryCols, raw_markdown, content',
        )
        .eq('user_id', _userId)
        .eq('date', isoDate)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Blocks ordered for read display.
  ///
  /// `user_id` filter is redundant with the `diary_blocks` RLS SELECT
  /// policy (which would already hide other users' private blocks
  /// and only surface their public / connected / category ones), but
  /// we add it client-side as defense-in-depth — audit M1. Without
  /// the explicit filter, a future caller passing an arbitrary
  /// `diary_id` could silently get an RLS-trimmed mix instead of
  /// an empty result, which would mask a logic bug.
  Future<List<Map<String, dynamic>>> blocksFor(int diaryId) async {
    return await _client
        .from('diary_blocks')
        .select('id, block_order, content, original_scope, '
            'effective_scope, category_id')
        .eq('diary_id', diaryId)
        .eq('user_id', _userId)
        .order('block_order', ascending: true);
  }

  /// Calls the `search_diary_blocks` ILIKE RPC (security invoker, so
  /// RLS applies). Filters client-side to own user_id — the RPC
  /// signature doesn't accept a user filter, so without this a
  /// matching public block from another user would consume one of
  /// our [limit] slots.
  Future<List<Map<String, dynamic>>> searchOwn(
    String query, {
    int limit = 20,
  }) async {
    // Over-fetch so client-side filtering still has enough hits to
    // satisfy [limit] when the user's diaries are mixed with public
    // matches from others.
    final raw = await _client.rpc(
      'search_diary_blocks',
      params: {
        'search_query': query,
        'limit_count': limit * 4,
        'offset_count': 0,
      },
    ) as List;
    return raw
        .cast<Map<String, dynamic>>()
        .where((r) => r['user_id'] == _userId)
        .take(limit)
        .toList();
  }

  /// Paginated own-diary read for export. PostgREST caps a single
  /// response at 1000 rows; we page by date so the export command
  /// can cover any number of diaries without bumping into that cap.
  Stream<Map<String, dynamic>> streamForExport({
    required DateTime from,
    required DateTime to,
    int pageSize = 500,
  }) async* {
    DateTime cursorTo = to;
    while (true) {
      final base = _client
          .from('diaries')
          .select('id, date, raw_markdown, content')
          .eq('user_id', _userId);
      final filtered =
          _applyDateRange(base, from, cursorTo).order('date', ascending: false);
      final page = await filtered.limit(pageSize);
      if (page.isEmpty) return;
      for (final row in page) {
        yield row;
      }
      if (page.length < pageSize) return;
      // Next page ends one day before the oldest row in this page.
      final oldest =
          DateTime.parse(page.last['date'] as String).toUtc();
      cursorTo = oldest.subtract(const Duration(days: 1));
      if (cursorTo.isBefore(from)) return;
    }
  }

  /// Upsert the diary row by (user_id, date) and replace its block
  /// list via the `upsert_diary_blocks` RPC.
  ///
  /// `diaries (user_id, date)` is UNIQUE so the row create/update is
  /// idempotent for the same author + day. The RPC then deletes the
  /// existing diary_blocks for that diary_id and re-inserts all of
  /// [blocks] in a single transaction, validating each block's
  /// category_id against `user_categories` (invalid ones get scope
  /// downgraded to private server-side — see migration
  /// 20260208100000_fix_upsert_blocks_invalid_category.sql).
  ///
  /// Returns `(diaryId, blockCount)` so the caller can render a
  /// summary message.
  Future<({int diaryId, int blockCount, DateTime updatedAt})> saveDiary({
    required DateTime date,
    required String rawMarkdown,
    required String visibility,
    required List<StoredBlock> blocks,
  }) async {
    final isoDate = date.toIso8601String().substring(0, 10);
    final upserted = await _client
        .from('diaries')
        .upsert(
          {
            'user_id': _userId,
            'date': isoDate,
            'visibility': visibility,
            'base_scope': visibility,
            'raw_markdown': rawMarkdown,
            // The legacy `content` column is kept in sync with
            // raw_markdown so older code paths that still read it
            // (and the search RPC which JOINs through diaries) get
            // identical text. Matches Flutter's write contract.
            'content': rawMarkdown,
            'body': extractBody(rawMarkdown),
            'char_count': computeCharCount(rawMarkdown),
            'partials_active': true,
          },
          onConflict: 'user_id,date',
        )
        .select('id')
        .single();
    final diaryId = upserted['id'] as int;

    final blockPayload = <Map<String, dynamic>>[
      for (var i = 0; i < blocks.length; i++)
        {
          'content': blocks[i].content,
          'original_scope': blocks[i].scope,
          'block_order': i,
          if (blocks[i].categoryId != null)
            'category_id': blocks[i].categoryId,
        },
    ];

    await _client.rpc('upsert_diary_blocks', params: {
      'p_diary_id': diaryId,
      'p_blocks': blockPayload,
    });

    // After upsert_diary_blocks bumps diaries.updated_at, re-read the
    // canonical value so the LastWriteStore preempt check has the
    // exact server-side timestamp to compare against later.
    final after = await _client
        .from('diaries')
        .select('updated_at')
        .eq('id', diaryId)
        .limit(1)
        .single();
    final updatedAt =
        DateTime.parse(after['updated_at'] as String).toUtc();

    return (diaryId: diaryId, blockCount: blocks.length, updatedAt: updatedAt);
  }

  /// Re-fetch the server-side `updated_at` for a diary the CLI
  /// previously wrote. Used by the preempt check on every command
  /// startup. Returns null when the row no longer exists (deleted
  /// from another client).
  Future<DateTime?> fetchUpdatedAt(int diaryId) async {
    final rows = await _client
        .from('diaries')
        .select('updated_at')
        .eq('id', diaryId)
        .limit(1);
    if (rows.isEmpty) return null;
    final value = rows.first['updated_at'];
    if (value is! String) return null;
    return DateTime.parse(value).toUtc();
  }

  /// Delete the diary for the given [date]. Returns whether a row
  /// was actually deleted (false when the date didn't exist).
  ///
  /// Routes through the `delete_diary_with_tombstone` RPC so a
  /// matching row gets a tombstone receipt; without it, Flutter's
  /// Drift cache wouldn't learn of the deletion and the next
  /// edit-then-push would grave-dig the diary (rm/list bug Option 2,
  /// see ~/life/works/taglibro-cli/list-rm-bug-investigation.md).
  Future<bool> deleteOwnByDate(DateTime date) async {
    // Find the id under our user_id first — the RPC takes a diary
    // id, not a (user, date) pair. Returning false for absent dates
    // keeps the command's exit-4 behaviour intact.
    final diary = await findOwnByDate(date);
    if (diary == null) return false;
    await _client.rpc(
      'delete_diary_with_tombstone',
      params: {'p_diary_id': diary['id']},
    );
    return true;
  }

  /// Inclusive `date >= from AND date <= to` chaining helper. The
  /// PostgrestTransformBuilder builder type changes across supabase-
  /// dart versions, so we keep the dynamic until the package locks
  /// the surface API.
  static dynamic _applyDateRange(
    dynamic builder,
    DateTime? from,
    DateTime? to,
  ) {
    var b = builder;
    if (from != null) {
      b = b.gte('date', from.toIso8601String().substring(0, 10));
    }
    if (to != null) {
      b = b.lte('date', to.toIso8601String().substring(0, 10));
    }
    return b;
  }
}
