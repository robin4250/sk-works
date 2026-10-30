import 'package:supabase_flutter/supabase_flutter.dart';

/// Notes/albums use chat destinations, not the private LINE analysis workspace.
/// Classify by server-provided IDs, never by a group's editable name or suffix.
Future<List<Map<String, dynamic>>> loadChatResourceGroups(
  SupabaseClient client,
  String companyId,
) async {
  final analysisIds = <String>{};
  try {
    final raw = await client.rpc('line_history_analysis_ids');
    if (raw is! List || raw.any((id) => id is! String)) {
      throw StateError('分析先の区分を取得できませんでした。');
    }
    analysisIds.addAll(raw.cast<String>());
  } on PostgrestException catch (error) {
    // Same rollout compatibility as ChatCloudRepository: before this additive
    // migration there are no classified analysis destinations.
    if (error.code != 'PGRST202' && error.code != '42883') rethrow;
  }
  final rows = await client
      .from('communication_groups')
      .select('id, name, site_id, group_type')
      .eq('company_id', companyId)
      .order('name');
  return rows
      .where((row) => !analysisIds.contains(row['id']))
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
