import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:taglibro_cli/src/util/last_write_store.dart';

void main() {
  late Directory tmp;
  late LastWriteStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('taglibro-lws-');
    store = LastWriteStore(
      overridePath: p.join(tmp.path, 'last_writes.json'),
    );
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('load() returns empty when the file does not exist', () {
    expect(store.load(), isEmpty);
  });

  test('append → load round-trip preserves every field', () {
    final at = DateTime.utc(2026, 5, 14, 11, 0, 0);
    final date = DateTime.utc(2026, 5, 14);
    store.append(LastWriteRecord(
      diaryId: 42,
      updatedAt: at,
      diaryDate: date,
    ));

    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.diaryId, 42);
    expect(loaded.first.updatedAt.isAtSameMomentAs(at), isTrue);
    expect(loaded.first.diaryDate.isAtSameMomentAs(date), isTrue);
  });

  test('append() replaces a record for the same diaryId', () {
    final t0 = DateTime.utc(2026, 5, 14, 10);
    final t1 = DateTime.utc(2026, 5, 14, 12);
    store
      ..append(LastWriteRecord(
        diaryId: 1,
        updatedAt: t0,
        diaryDate: DateTime.utc(2026, 5, 14),
      ))
      ..append(LastWriteRecord(
        diaryId: 1,
        updatedAt: t1,
        diaryDate: DateTime.utc(2026, 5, 14),
      ));

    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.updatedAt.isAtSameMomentAs(t1), isTrue);
  });

  test('append() evicts the oldest past maxRecords', () {
    final base = DateTime.utc(2026, 5, 14, 10);
    for (var i = 0; i < LastWriteStore.maxRecords + 3; i++) {
      store.append(LastWriteRecord(
        diaryId: 100 + i,
        updatedAt: base.add(Duration(minutes: i)),
        diaryDate: DateTime.utc(2026, 5, 14),
      ));
    }
    final loaded = store.load();
    expect(loaded, hasLength(LastWriteStore.maxRecords));
    // Newest first, so the first record is the last one appended.
    expect(loaded.first.diaryId, 100 + LastWriteStore.maxRecords + 2);
  });

  test('clear() removes the file', () {
    store.append(LastWriteRecord(
      diaryId: 1,
      updatedAt: DateTime.utc(2026, 5, 14, 11),
      diaryDate: DateTime.utc(2026, 5, 14),
    ));
    expect(File(store.resolvePath()).existsSync(), isTrue);
    store.clear();
    expect(File(store.resolvePath()).existsSync(), isFalse);
    expect(store.load(), isEmpty);
  });

  test('malformed JSON returns empty list instead of throwing', () {
    File(store.resolvePath()).writeAsStringSync('not json');
    expect(store.load(), isEmpty);
  });

  test('replaceAll() persists exactly the given list', () {
    final a = LastWriteRecord(
      diaryId: 1,
      updatedAt: DateTime.utc(2026, 5, 14, 10),
      diaryDate: DateTime.utc(2026, 5, 14),
    );
    final b = LastWriteRecord(
      diaryId: 2,
      updatedAt: DateTime.utc(2026, 5, 14, 11),
      diaryDate: DateTime.utc(2026, 5, 14),
    );
    store.replaceAll([a, b]);
    final loaded = store.load();
    expect(loaded.map((r) => r.diaryId), [1, 2]);
  });
}
