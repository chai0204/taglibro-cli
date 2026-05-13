import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'package:taglibro_cli/src/data/diary_repo.dart';

void main() {
  group('DiaryRepo.blocksFor (audit M1)', () {
    // Captures every request the SupabaseClient makes so we can
    // inspect the PostgREST query string after the call returns. The
    // empty 200 body is enough for blocksFor to return — the focus
    // of the test is what's *on the wire*, not the parse.
    late List<Uri> capturedUrls;
    late SupabaseClient client;
    late DiaryRepo repo;

    setUp(() {
      capturedUrls = <Uri>[];
      final mock = MockClient((req) async {
        capturedUrls.add(req.url);
        // PostgREST's response parser does `response.request!`
        // unconditionally to decide whether to skip the body
        // (HEAD requests), so we have to thread the original
        // request back onto the Response. content-range is also
        // expected for ranged GETs.
        return http.Response(
          '[]',
          200,
          request: req,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/0',
          },
        );
      });
      client = SupabaseClient(
        'http://supabase.local',
        'fake-anon-key',
        httpClient: mock,
      );
      repo = DiaryRepo(client, 'user-aaaa');
    });

    test('adds a user_id eq filter alongside diary_id', () async {
      await repo.blocksFor(42);

      expect(capturedUrls, hasLength(1));
      final query = capturedUrls.single.query;
      expect(query, contains('diary_id=eq.42'));
      // defense-in-depth filter — the actual point of the M1 fix.
      expect(query, contains('user_id=eq.user-aaaa'));
    });

    test('keeps the block_order asc ordering', () async {
      await repo.blocksFor(42);
      final query = capturedUrls.single.query;
      // Match the relaxed PostgREST `order=col.dir` shape — the SDK
      // sometimes URL-encodes the dot, so accept either spelling.
      expect(
        query,
        anyOf(
          contains('order=block_order.asc'),
          contains('order=block_order'),
        ),
      );
    });

    test('hits the /diary_blocks REST endpoint, not /diaries', () async {
      await repo.blocksFor(42);
      expect(capturedUrls.single.path, contains('/diary_blocks'));
    });
  });

  group('DiaryRepo.deleteOwnByDate (rm/list bug Option 2)', () {
    // The CLI rm path must route through the
    // `delete_diary_with_tombstone` RPC so Flutter's Drift cache
    // can reconcile via pullAndMerge. A bare DELETE would leave
    // the diary "alive" in Drift and grave-dig on next edit.
    test('first looks up the diary id, then calls the RPC', () async {
      final captured = <_Request>[];
      final mock = MockClient((req) async {
        captured.add(_Request(req.method, req.url));
        // Two responses needed: the findOwnByDate select returns a
        // diary row, then the RPC call returns null.
        if (req.url.path.contains('/diaries') && req.method == 'GET') {
          return http.Response(
            '[{"id": 42, "user_id": "user-bb", "date": "2026-05-13", '
            '"visibility": "private", "char_count": 1, "body": "x", '
            '"base_scope": "private", "raw_markdown": "x", '
            '"content": "x", "created_at": "2026-05-13T00:00:00Z", '
            '"updated_at": "2026-05-13T00:00:00Z"}]',
            200,
            request: req,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/1',
            },
          );
        }
        return http.Response(
          'null',
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = SupabaseClient(
        'http://supabase.local',
        'fake-anon-key',
        httpClient: mock,
      );
      final repo = DiaryRepo(client, 'user-bb');

      final deleted =
          await repo.deleteOwnByDate(DateTime.utc(2026, 5, 13));
      expect(deleted, isTrue);

      // 1) GET on /diaries with the date + user filter
      // 2) POST on /rpc/delete_diary_with_tombstone
      expect(captured, hasLength(2));
      expect(captured.first.url.path, contains('/diaries'));
      expect(captured.first.method, 'GET');
      expect(captured.last.url.path,
          contains('/rpc/delete_diary_with_tombstone'));
      expect(captured.last.method, 'POST');
    });

    test('returns false when the date has no matching diary', () async {
      final mock = MockClient((req) async {
        // Empty result from the find call.
        return http.Response(
          '[]',
          200,
          request: req,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/0',
          },
        );
      });
      final client = SupabaseClient(
        'http://supabase.local',
        'fake-anon-key',
        httpClient: mock,
      );
      final repo = DiaryRepo(client, 'user-bb');

      final deleted =
          await repo.deleteOwnByDate(DateTime.utc(2026, 5, 13));
      expect(deleted, isFalse);
    });
  });
}

class _Request {
  final String method;
  final Uri url;
  const _Request(this.method, this.url);
}
