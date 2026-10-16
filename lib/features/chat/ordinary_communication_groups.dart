import 'package:supabase_flutter/supabase_flutter.dart';

/// LINE workspaces stay in LINE Talk, outside ordinary notes/albums pickers.
/// Classify by stored IDs, never by editable group names.
Future<List<Map<String, dynamic>>> ordinaryCommunicationGroups(
  SupabaseClient client, String companyId,
) async {
  final actor = client.auth.currentUser?.id;
  if (actor == null) throw StateError('ログインが必要です。');
  final excluded = <String>{};
  try {
    final raw = await client.rpc('line_history_analysis_ids');
    if (raw is! List) throw StateError('分析先の区分を取得できませんでした。');
    excluded.addAll(raw.map((id) => id.toString()));
  } on PostgrestException catch (error) {
    // Older servers cannot contain dedicated analysis destinations.
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }
  try {
    final raw = await client.rpc('line_shared_chat_groups');
    if (raw is! List) throw StateError('LINE区分を取得できませんでした。');
    for (final row in raw.whereType<Map>()) {
      if (row['origin'] == 'line') excluded.add(row['group_id'].toString());
    }
  } on PostgrestException catch (error) {
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }
  final bindings = await client.from('line_group_bindings')
      .select('communication_group_id').eq('company_id', companyId);
  for (final row in bindings) {
    final id = row['communication_group_id'];
    if (id is String) excluded.add(id);
  }
  final rows = await client.from('communication_groups')
      .select('id, name, site_id, group_type')
      .eq('company_id', companyId).order('name');
  if (client.auth.currentUser?.id != actor) {
    throw StateError('ログイン状態が変わりました。');
  }
  return List<Map<String, dynamic>>.from(rows)
      .where((row) => !excluded.contains(row['id'])).toList(growable: false);
}
