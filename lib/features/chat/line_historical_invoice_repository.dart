import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'line_import_repository.dart';

class LineHistoricalInvoiceRepository {
  LineHistoricalInvoiceRepository(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  static LineHistoricalInvoiceRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? LineHistoricalInvoiceRepository(SupabaseBackend.client) : null;
  Future<Map<String, dynamic>> _rpc(String name, Map<String, dynamic> params) async {
    final actor = client.auth.currentUser?.id;
    if (actor == null || actor != _owner) throw StateError('ログインが変わりました。');
    final data = await client.rpc(name, params: params);
    if (client.auth.currentUser?.id != actor || data is! Map) throw StateError('取得結果を確認できません。');
    return Map<String, dynamic>.from(data);
  }
  String monthKey(DateTime month) => '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
  Future<Map<String, dynamic>> load(String group, DateTime month) => _rpc('line_historical_quote_workspace', {'p_group_id': group, 'p_month': monthKey(month)});
  Map<String, dynamic> command(String group, DateTime month, Map<String, dynamic> data, List<Map<String, dynamic>> rates) => {
    'p_command_id': LineImportRepository.commandId(), 'p_group_id': group,
    'p_month': monthKey(month), 'p_draft_id': data['draft_id'],
    'p_revision': data['revision'], 'p_fingerprint': data['fingerprint'], 'p_rates': rates,
  };
  Future<Map<String, dynamic>> save(Map<String, dynamic> command) => _rpc('save_line_historical_quote', command);
}
