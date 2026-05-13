import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/category_repo.dart';
import '../util/cli_run.dart';
import '../util/prompt.dart';

/// Owner-side category management. Parent command with five
/// subcommands; mirrors the Flutter category-management sheet.
///
/// Pre-1.0 the Flutter UI queried `.select('id, name, color')` on
/// `user_categories` without the matching column ever existing —
/// migration `20260513110000_user_categories_color` adds it. CLI
/// commands here speak the same shape.
class CategoryCommand extends Command<int> {
  CategoryCommand() {
    addSubcommand(_ListCategoriesCommand());
    addSubcommand(_AddCategoryCommand());
    addSubcommand(_RmCategoryCommand());
    addSubcommand(_AssignCategoryCommand());
    addSubcommand(_UnassignCategoryCommand());
  }

  @override
  final name = 'category';
  @override
  final description = 'Manage your connection categories.';
}

String _env(Command<int> cmd) =>
    (cmd.globalResults?['env'] as String?) ?? 'prod';

bool _asJson(Command<int> cmd) =>
    (cmd.globalResults?['json'] as bool?) ?? false;

// ── list ────────────────────────────────────────────────────────────

class _ListCategoriesCommand extends Command<int> {
  @override
  final name = 'list';
  @override
  final description = 'List your own categories, alphabetised.';

  @override
  Future<int> run() async {
    final asJson = _asJson(this);
    return runWithSignedInClient(
      env: _env(this),
      body: (client, userId) async {
        final cats = await CategoryRepo(client, userId).listOwn();
        if (asJson) {
          stdout.writeln(jsonEncode(cats
              .map((c) =>
                  {'id': c.id, 'name': c.name, 'color': c.color})
              .toList()));
          return 0;
        }
        if (cats.isEmpty) {
          stderr.writeln('(no categories)');
          return 0;
        }
        for (final c in cats) {
          stdout.writeln('${c.id}  ${c.color}  ${c.name}');
        }
        return 0;
      },
    );
  }
}

// ── add ─────────────────────────────────────────────────────────────

class _AddCategoryCommand extends Command<int> {
  _AddCategoryCommand() {
    argParser.addOption(
      'color',
      defaultsTo: '#6650C7',
      help: 'Hex colour shown next to the category name in the UI.',
    );
  }

  @override
  final name = 'add';
  @override
  final description = 'Create a new category. Positional arg is the name.';

  @override
  Future<int> run() async {
    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: taglibro category add <name> [--color=#XXXXXX]');
      return 1;
    }
    final name = positional.join(' ').trim();
    if (name.isEmpty) {
      stderr.writeln('Category name is empty.');
      return 1;
    }
    final color = argResults!['color'] as String;
    return runWithSignedInClient(
      env: _env(this),
      body: (client, userId) async {
        final created =
            await CategoryRepo(client, userId).create(name: name, color: color);
        if (_asJson(this)) {
          stdout.writeln(jsonEncode({
            'id': created.id,
            'name': created.name,
            'color': created.color,
          }));
        } else {
          stdout.writeln(
              '✓ カテゴリ "${created.name}" を作成しました (${created.id})');
        }
        return 0;
      },
    );
  }
}

// ── rm ──────────────────────────────────────────────────────────────

class _RmCategoryCommand extends Command<int> {
  _RmCategoryCommand() {
    argParser.addFlag(
      'yes',
      negatable: false,
      help: 'Skip the confirmation prompt.',
    );
  }

  @override
  final name = 'rm';
  @override
  final description = 'Delete a category (downgrades referenced blocks '
      'to private first via the archive_category RPC).';

  @override
  Future<int> run() async {
    final positional = argResults!.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: taglibro category rm <category-id> [--yes]');
      return 1;
    }
    final id = positional.first;
    final skipConfirm = argResults!['yes'] as bool;

    return runWithSignedInClient(
      env: _env(this),
      body: (client, userId) async {
        if (!skipConfirm) {
          final ok = confirm(
            'カテゴリ $id を削除します。所属していたブロックは private に '
            '降格されます。よろしいですか?',
          );
          if (!ok) {
            stderr.writeln('aborted');
            return 1;
          }
        }
        await CategoryRepo(client, userId).delete(id);
        stdout.writeln('✓ カテゴリ $id を削除しました');
        return 0;
      },
    );
  }
}

// ── assign ──────────────────────────────────────────────────────────

class _AssignCategoryCommand extends Command<int> {
  @override
  final name = 'assign';
  @override
  final description =
      'Add a connection to a category. Args: <category-id> <user-id>.';

  @override
  Future<int> run() async {
    final positional = argResults!.rest;
    if (positional.length < 2) {
      stderr.writeln('Usage: taglibro category assign <category-id> <user-id>');
      return 1;
    }
    final categoryId = positional[0];
    final connectedUserId = positional[1];
    return runWithSignedInClient(
      env: _env(this),
      body: (client, userId) async {
        await CategoryRepo(client, userId).assign(
          categoryId: categoryId,
          connectedUserId: connectedUserId,
        );
        stdout.writeln(
            '✓ ユーザー $connectedUserId をカテゴリ $categoryId に追加しました');
        return 0;
      },
    );
  }
}

// ── unassign ────────────────────────────────────────────────────────

class _UnassignCategoryCommand extends Command<int> {
  @override
  final name = 'unassign';
  @override
  final description =
      'Remove a connection from a category. Args: <category-id> <user-id>.';

  @override
  Future<int> run() async {
    final positional = argResults!.rest;
    if (positional.length < 2) {
      stderr.writeln(
          'Usage: taglibro category unassign <category-id> <user-id>');
      return 1;
    }
    final categoryId = positional[0];
    final connectedUserId = positional[1];
    return runWithSignedInClient(
      env: _env(this),
      body: (client, userId) async {
        await CategoryRepo(client, userId).unassign(
          categoryId: categoryId,
          connectedUserId: connectedUserId,
        );
        stdout.writeln(
            '✓ ユーザー $connectedUserId をカテゴリ $categoryId から外しました');
        return 0;
      },
    );
  }
}
