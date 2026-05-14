import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../auth/credentials_store.dart';

/// One record of "I wrote diary X at time T; server confirmed
/// updated_at = U". The store keeps a short rolling list so the
/// preempt check on every CLI command can detect "somebody else
/// wrote to one of these rows after I did" without holding state
/// for the entire user history.
class LastWriteRecord {
  /// Server-side diary id (`diaries.id`). Used as the lookup key
  /// for the post-hoc `updated_at` re-fetch.
  final int diaryId;

  /// Server-confirmed `updated_at` at the moment of our write. If a
  /// later check finds the row's `updated_at` strictly greater than
  /// this, another client moved the row.
  final DateTime updatedAt;

  /// Diary's calendar date — purely for the user-visible warning
  /// message, not for matching.
  final DateTime diaryDate;

  const LastWriteRecord({
    required this.diaryId,
    required this.updatedAt,
    required this.diaryDate,
  });

  Map<String, dynamic> toJson() => {
        'diary_id': diaryId,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'diary_date': diaryDate.toUtc().toIso8601String(),
      };

  static LastWriteRecord? fromJson(Map<String, dynamic> json) {
    final id = json['diary_id'];
    final u = json['updated_at'];
    final d = json['diary_date'];
    if (id is! int || u is! String || d is! String) return null;
    return LastWriteRecord(
      diaryId: id,
      updatedAt: DateTime.parse(u),
      diaryDate: DateTime.parse(d),
    );
  }
}

/// Disk-backed list of recent CLI writes used by the preempt check.
///
/// Path: `$XDG_CONFIG_HOME/taglibro/last_writes.json` (POSIX) or
/// `%APPDATA%\taglibro\last_writes.json` (Windows). Shares the
/// platform location logic with `CredentialsStore.resolveDefaultPath`
/// so a user wiping `~/.config/taglibro/` blows away both files
/// atomically.
class LastWriteStore {
  /// Cap on the number of records kept on disk. New writes evict
  /// the oldest. 10 is enough: the preempt check is opportunistic
  /// "did your last few writes get overridden?" — older history is
  /// covered by Flutter's persistent preempt_log.
  static const int maxRecords = 10;

  /// Override for tests; null means use the default path under the
  /// OS-appropriate config directory.
  final String? overridePath;

  const LastWriteStore({this.overridePath});

  String resolvePath() {
    if (overridePath != null) return overridePath!;
    final base = CredentialsStore.resolveDefaultPath(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
    return p.join(p.dirname(base), 'last_writes.json');
  }

  /// Returns the records currently on disk, newest first. Missing /
  /// malformed file → empty list.
  List<LastWriteRecord> load() {
    final file = File(resolvePath());
    if (!file.existsSync()) return const [];
    try {
      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(LastWriteRecord.fromJson)
          .whereType<LastWriteRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Append [record] and persist, evicting the oldest entries past
  /// [maxRecords]. If a record for the same `diaryId` already exists,
  /// the older one is replaced (so the user's *latest* write per
  /// diary is what we check against).
  void append(LastWriteRecord record) {
    final existing = load().where((r) => r.diaryId != record.diaryId).toList();
    final updated = [record, ...existing].take(maxRecords).toList();
    _writeAll(updated);
  }

  /// Persist [records] verbatim. Used by the preempt check to drop
  /// already-reported entries.
  void replaceAll(List<LastWriteRecord> records) => _writeAll(records);

  /// Drop every record. Called on logout.
  void clear() {
    final file = File(resolvePath());
    if (file.existsSync()) file.deleteSync();
  }

  void _writeAll(List<LastWriteRecord> records) {
    final path = resolvePath();
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tmp = File('$path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert(records.map((r) => r.toJson()).toList()),
      flush: true,
    );
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', tmp.path]);
    }
    if (Platform.isWindows && File(path).existsSync()) {
      File(path).deleteSync();
    }
    tmp.renameSync(path);
  }
}
