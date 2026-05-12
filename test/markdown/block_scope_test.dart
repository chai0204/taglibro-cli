import 'package:test/test.dart';

import 'package:taglibro_cli/src/markdown/block_scope.dart';

void main() {
  group('parseTaggedMarkdown — non-fenced bodies', () {
    test('empty input returns no blocks', () {
      expect(
        parseTaggedMarkdown('', baseScope: 'public'),
        isEmpty,
      );
    });

    test('plain paragraph: one block at baseScope', () {
      final blocks = parseTaggedMarkdown(
        'just a single paragraph.',
        baseScope: 'private',
      );
      expect(blocks, hasLength(1));
      expect(blocks.first.content, 'just a single paragraph.');
      expect(blocks.first.scope, 'private');
      expect(blocks.first.categoryId, isNull);
    });

    test('headings and lists pass through as one base-scope block', () {
      final md = '# 見出し\n\n- 一\n- 二\n1. リストアイテム';
      final blocks = parseTaggedMarkdown(md, baseScope: 'public');
      expect(blocks, hasLength(1));
      expect(blocks.first.content, contains('見出し'));
      expect(blocks.first.content, contains('リストアイテム'));
      expect(blocks.first.scope, 'public');
    });
  });

  group('parseTaggedMarkdown — scope fences', () {
    test('#public fence emits a single public block', () {
      final md = '```#public\npublic body\n```';
      final blocks = parseTaggedMarkdown(md, baseScope: 'private');
      expect(blocks, hasLength(1));
      expect(blocks.first.scope, 'public');
      expect(blocks.first.content, 'public body');
    });

    test('#connect and #connected are equivalent', () {
      final a = parseTaggedMarkdown('```#connect\na\n```', baseScope: 'private');
      final b = parseTaggedMarkdown('```#connected\nb\n```', baseScope: 'private');
      expect(a.single.scope, 'connected');
      expect(b.single.scope, 'connected');
    });

    test('#private fence forces private regardless of baseScope', () {
      final blocks = parseTaggedMarkdown(
        '```#private\nsecret\n```',
        baseScope: 'public',
      );
      expect(blocks.single.scope, 'private');
    });

    test('#cat:<valid-uuid> emits a category block with the uuid', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      final blocks = parseTaggedMarkdown(
        '```#cat:$uuid\ncategory body\n```',
        baseScope: 'public',
      );
      expect(blocks.single.scope, 'category');
      expect(blocks.single.categoryId, uuid);
    });

    test('#cat:<bad-uuid> downgrades to private (no accidental leak)', () {
      final blocks = parseTaggedMarkdown(
        '```#cat:not-a-uuid\nbody\n```',
        baseScope: 'public',
      );
      expect(blocks.single.scope, 'private');
      expect(blocks.single.categoryId, isNull);
    });

    test('non-scope fences inherit baseScope', () {
      final blocks = parseTaggedMarkdown(
        '```python\nprint("hi")\n```',
        baseScope: 'public',
      );
      expect(blocks.single.scope, 'public');
      expect(blocks.single.content, 'print("hi")');
    });

    test('mixed body splits into ordered blocks with correct scopes', () {
      final md = '''preamble paragraph

```#public
shared note
```

middle paragraph

```#connect
friend-only
```

trailing paragraph''';

      final blocks = parseTaggedMarkdown(md, baseScope: 'private');
      expect(blocks.map((b) => b.scope).toList(),
          ['private', 'public', 'private', 'connected', 'private']);
      expect(blocks[0].content, 'preamble paragraph');
      expect(blocks[1].content, 'shared note');
      expect(blocks[4].content, 'trailing paragraph');
    });
  });

  group('parseTaggedMarkdown — edge cases', () {
    test('unclosed scope fence leaves the trailing text as base-scope', () {
      // Regex won't match the open fence without a closing one, so
      // the whole document falls through as a single base-scope block.
      final blocks = parseTaggedMarkdown(
        '```#public\nstart but never closed',
        baseScope: 'private',
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.scope, 'private');
      expect(blocks.single.content, contains('start but never closed'));
    });

    test('empty fence body is skipped (no empty block)', () {
      final blocks = parseTaggedMarkdown(
        'before\n\n```#public\n\n```\n\nafter',
        baseScope: 'private',
      );
      // Only the surrounding paragraphs remain.
      expect(blocks.map((b) => b.content), ['before', 'after']);
    });

    test('whitespace-only input returns no blocks', () {
      expect(
        parseTaggedMarkdown('   \n\n\t  \n', baseScope: 'public'),
        isEmpty,
      );
    });
  });

  group('computeCharCount / extractBody', () {
    test('computeCharCount ignores fences and markdown decorators', () {
      const md = '# Title\n\n**bold** word\n\n```python\nfoo\n```';
      final n = computeCharCount(md);
      // 'Titleboldword' (markdown decorators + the fenced code drop
      // out). Code block content drops out, decorators do too.
      expect(n, 'Titleboldword'.runes.length);
    });

    test('extractBody returns the first non-empty, non-heading line', () {
      const md = '# Heading\n\n本文の最初の行\n後続行';
      expect(extractBody(md), '本文の最初の行');
    });

    test('extractBody falls through to trimmed markdown when no body found',
        () {
      expect(extractBody('   '), '');
      expect(extractBody('# Only a heading'), '# Only a heading');
    });
  });
}
