/// Pure-Dart subset of `lib/features/editor/domain/block_scope.dart`
/// (Flutter). Only the markdown→blocks splitter is needed here; the
/// AppFlowy [Document] reconstruction lives Flutter-side and isn't
/// useful on a headless CLI.
///
/// **Drift risk.** If the Flutter side adds a new scope tag or
/// changes the regex, the CLI must follow. There's no compile-time
/// check tying these two copies together — Phase D plans to lift
/// this code into a `packages/taglibro_core/` workspace member so
/// both clients depend on a single source. Until then, treat the
/// Flutter version as canonical and mirror changes here by hand.
library;

/// One stored block as persisted to `diary_blocks`.
///
/// Pure data; mirrors `lib/features/editor/domain/entities/stored_block.dart`.
class StoredBlock {
  const StoredBlock({
    required this.content,
    required this.scope,
    this.categoryId,
  });

  /// Markdown body (same shape stored in `diary_blocks.content`).
  final String content;

  /// One of `'public'` / `'connected'` / `'private'` / `'category'`.
  final String scope;

  /// Category id when [scope] is `'category'`, otherwise null.
  final String? categoryId;
}

/// Parse a raw markdown string into a list of [StoredBlock]s using
/// the legacy Next.js tag-markup convention:
///
/// ```
/// ```#public
/// body goes here
/// ```
/// ```
///
/// Supported tags (priority order):
///   - `#public`                 → scope `'public'`
///   - `#connect` / `#connected` → scope `'connected'`
///   - `#cat:<uuid>`             → scope `'category'` with that category id
///   - `#private`                → scope `'private'`
///   - anything else             → [baseScope]
///
/// Non-tagged surrounding text becomes its own block with [baseScope].
List<StoredBlock> parseTaggedMarkdown(
  String markdown, {
  required String baseScope,
}) {
  final result = <StoredBlock>[];
  if (markdown.isEmpty) return result;

  final pattern = RegExp(r'```([^\n]*)\n([\s\S]*?)```');
  var cursor = 0;

  for (final match in pattern.allMatches(markdown)) {
    if (match.start > cursor) {
      final before = markdown.substring(cursor, match.start).trim();
      if (before.isNotEmpty) {
        result.add(StoredBlock(content: before, scope: baseScope));
      }
    }

    final header = match.group(1) ?? '';
    final content = (match.group(2) ?? '').trim();
    final decision = _decideScopeFromTags(header, baseScope: baseScope);
    if (content.isNotEmpty) {
      result.add(StoredBlock(
        content: content,
        scope: decision.scope,
        categoryId: decision.categoryId,
      ));
    }

    cursor = match.end;
  }

  if (cursor < markdown.length) {
    final trailing = markdown.substring(cursor).trim();
    if (trailing.isNotEmpty) {
      result.add(StoredBlock(content: trailing, scope: baseScope));
    }
  }

  // No tagged blocks at all: return the whole document as one block.
  if (result.isEmpty) {
    final trimmed = markdown.trim();
    if (trimmed.isNotEmpty) {
      result.add(StoredBlock(content: trimmed, scope: baseScope));
    }
  }

  return result;
}

class _ScopeDecision {
  const _ScopeDecision(this.scope, this.categoryId);
  final String scope;
  final String? categoryId;
}

final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

_ScopeDecision _decideScopeFromTags(
  String header, {
  required String baseScope,
}) {
  final tagRe = RegExp(r'#([a-zA-Z0-9:\-_]+)');
  final tags =
      tagRe.allMatches(header).map((m) => m.group(1)!.toLowerCase()).toList();

  if (tags.contains('public')) return const _ScopeDecision('public', null);
  if (tags.contains('connect') || tags.contains('connected')) {
    return const _ScopeDecision('connected', null);
  }
  for (final tag in tags) {
    if (tag.startsWith('cat:')) {
      final uuid = tag.substring(4);
      if (_uuidRe.hasMatch(uuid)) {
        return _ScopeDecision('category', uuid);
      }
      // Invalid UUID: fall back to private to avoid accidental leaks.
      return const _ScopeDecision('private', null);
    }
  }
  if (tags.contains('private')) return const _ScopeDecision('private', null);
  return _ScopeDecision(baseScope, null);
}

/// Count *visible* characters in the markdown — same definition the
/// Flutter app uses for `diaries.char_count`. We strip whitespace
/// runs and fence markers so the displayed value matches what a
/// reader would think they're reading. Not exact parity with the
/// Flutter `DiaryEntity.computeCharCount` (which depends on
/// AppFlowy node semantics), but close enough for the CLI; the
/// next edit from Flutter overwrites it anyway.
int computeCharCount(String markdown) {
  final stripped = markdown
      .replaceAll(RegExp(r'```[^\n]*\n[\s\S]*?```'), '')
      .replaceAll(RegExp(r'[*_~`>#\-]'), '')
      .replaceAll(RegExp(r'\s+'), '');
  return stripped.runes.length;
}

/// First paragraph-ish line for `diaries.body` — the preview shown
/// on home / list. Approximation of Flutter's `_extractBody`; same
/// caveat as [computeCharCount].
String extractBody(String markdown) {
  for (final line in markdown.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('```')) continue;
    if (t.startsWith('#')) continue;
    return t;
  }
  return markdown.trim();
}
