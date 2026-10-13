import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'line_import_repository.dart';

class LineHistoricalInvoiceBridgeRepository {
  LineHistoricalInvoiceBridgeRepository(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  static LineHistoricalInvoiceBridgeRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? LineHistoricalInvoiceBridgeRepository(SupabaseBackend.client) : null;
  Future<Map<String, dynamic>> _rpc(String name, Map<String, dynamic> params) async {
    final actor = client.auth.currentUser?.id;
    if (actor == null || actor != _owner) throw StateError('ログインが変わりました。');
    final raw = await client.rpc(name, params: params);
    if (client.auth.currentUser?.id != actor || raw is! Map) throw StateError('取得結果を確認できません。');
    return Map<String, dynamic>.from(raw);
  }
  Future<Map<String, dynamic>> load(String quoteId) => _rpc('line_historical_invoice_workspace', {'p_quote_id': quoteId});
  Future<Map<String, dynamic>> preview(Map<String, dynamic> params) => _rpc('line_historical_invoice_preview', params);
  Map<String, dynamic> command(Map<String, dynamic> params, String fingerprint) => Map<String, dynamic>.from(jsonDecode(jsonEncode({
    ...params, 'p_command_id': LineImportRepository.commandId(),
    'p_preview_fingerprint': fingerprint, 'p_preview_confirmed': true,
  })) as Map);
  Future<Map<String, dynamic>> create(Map<String, dynamic> params) => _rpc('create_line_historical_invoices', params);
}
