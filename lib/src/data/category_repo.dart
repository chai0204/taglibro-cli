import 'package:supabase/supabase.dart';

/// Single category row as the CLI sees it. Mirrors
/// `lib/features/connections/domain/entities/connection_category.dart`
/// on the Flutter side; the small set of fields keeps drift risk low
/// (cf. design.md §2 — copy + drift-guard pattern).
class Category {
  final String id;
  final String name;
  final String color;
  const Category({
    required this.id,
    required this.name,
    required this.color,
  });

  static Category fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        color: (json['color'] as String?) ?? '#6650C7',
      );
}

/// Membership row: (category, connected_user).
class CategoryAssignment {
  final String categoryId;
  final String connectedUserId;
  const CategoryAssignment({
    required this.categoryId,
    required this.connectedUserId,
  });
}

/// Owner-side category operations. Every method filters on the
/// signed-in user_id explicitly even when RLS would already cover
/// it — defense in depth (audit M1 pattern; see DiaryRepo for the
/// canonical rationale).
class CategoryRepo {
  final SupabaseClient _client;
  final String _userId;

  CategoryRepo(this._client, this._userId);

  /// All categories owned by the signed-in user, alphabetised by
  /// name for stable CLI output.
  Future<List<Category>> listOwn() async {
    final rows = await _client
        .from('user_categories')
        .select('id, name, color, user_id')
        .eq('user_id', _userId)
        .order('name', ascending: true) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  /// Insert a new category and return the persisted row (so the
  /// caller sees the server-assigned uuid + the resolved colour).
  Future<Category> create({required String name, required String color}) async {
    final rows = await _client
        .from('user_categories')
        .insert({'user_id': _userId, 'name': name, 'color': color})
        .select('id, name, color, user_id') as List;
    return Category.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Safe-delete via `archive_category` RPC: downgrades referencing
  /// blocks to `private` first, then drops the category. A plain
  /// DELETE would hit the `fk_category_requires_scope` CHECK if any
  /// block still references the category (verified by
  /// supabase/tests/category_rls.sql L5).
  Future<void> delete(String categoryId) async {
    await _client.rpc(
      'archive_category',
      params: {'p_category_id': categoryId},
    );
  }

  /// Add a connection to a category. Idempotent — the RLS layer
  /// enforces `user_id = auth.uid()` so this can only ever touch
  /// the caller's own categories.
  Future<void> assign({
    required String categoryId,
    required String connectedUserId,
  }) async {
    await _client.from('connection_categories').upsert({
      'user_id': _userId,
      'category_id': categoryId,
      'connected_user_id': connectedUserId,
    });
  }

  /// Remove a member from a category.
  Future<void> unassign({
    required String categoryId,
    required String connectedUserId,
  }) async {
    await _client
        .from('connection_categories')
        .delete()
        .eq('user_id', _userId)
        .eq('category_id', categoryId)
        .eq('connected_user_id', connectedUserId);
  }
}
