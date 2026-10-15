import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'line_reading_rules.dart';

class LineImportFeatures {
  const LineImportFeatures({this.attendance = false, this.invoice = false});
  final bool attendance, invoice;
  factory LineImportFeatures.fromJson(Object? value) {
    if (value is! Map || value['attendance'] is! bool || value['invoice'] is! bool) {
      throw StateError('LINE追加機能の設定を確認できません。');
    }
    return LineImportFeatures(attendance: value['attendance'] == true, invoice: value['invoice'] == true);
  }
}

class LineImportRepository {
  LineImportRepository(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  static LineImportRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? LineImportRepository(SupabaseBackend.client) : null;
  static String commandId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
  String get actor {
    final current = client.auth.currentUser?.id;
    if (current == null || current != _owner) throw StateError('ログインが変わりました。画面を開き直してください。');
    return current;
  }
  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    final captured = actor;
    final value = await client.rpc(name, params: params);
    if (client.auth.currentUser?.id != captured) throw StateError('ログインが変わりました。画面を開き直してください。');
    return value;
  }
  Future<LineImportFeatures> features() async => LineImportFeatures.fromJson(await _rpc('line_import_features', const {}));
  Future<List<LineReadingRule>> readingRules(String groupId) async {
    final value = await _rpc('line_reading_rules_workspace', {'p_group_id': groupId});
    if (value is! Map || value['rules'] is! List) {
      throw StateError('読み取り設定を確認できません。');
    }
    return [for (final rule in value['rules'] as List)
      LineReadingRule.fromJson(rule as Map)];
  }
  Future<List<Map<String, dynamic>>> destinations() async {
    final value = await _rpc('line_history_destinations', const {});
    if (value is! List) throw StateError('履歴の保存先を確認できません。');
    return [for (final row in value) Map<String, dynamic>.from(row as Map)];
  }
  Future<String> createAnalysis(String name, String commandId) async {
    final value = await _rpc('create_line_history_analysis', {'p_name': name, 'p_command_id': commandId});
    if (value is! String || value.isEmpty) throw StateError('分析用の保存先を作成できません。');
    return value;
  }
  Future<LineImportFeatures> setEnabled(String target, bool enabled) async => LineImportFeatures.fromJson(await _rpc('set_line_import_feature', {'p_target': target, 'p_enabled': enabled}));
  String _month(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-01';
  Map<String, dynamic> _workspace(Object? value) {
    if (value is! Map || value['revision'] is! int || value['can_edit'] is! bool || value['candidate_rows'] is! List || value['source_messages'] is! List) throw StateError('LINE取込データを確認できません。');
    return Map<String, dynamic>.from(value);
  }
  Future<Map<String, dynamic>> load(String groupId, String target, DateTime month) async => _workspace(await _rpc('line_import_workspace', {'p_group_id': groupId, 'p_target': target, 'p_month': _month(month)}));
  Map<String, dynamic> saveCommand({required String groupId, required String target, required DateTime month, required int revision,
      required String sourceKind, required List<Map<String, dynamic>> sources, required List<Map<String, dynamic>> rows, required String note, required bool confirmed}) => Map<String, dynamic>.from(jsonDecode(jsonEncode({
    'p_command_id': commandId(), 'p_group_id': groupId, 'p_target': target, 'p_month': _month(month), 'p_expected_revision': revision,
    'p_source_kind': sourceKind, 'p_sources': sources, 'p_rows': rows, 'p_note': note, 'p_confirmed': confirmed,
  })) as Map);
  Future<Map<String, dynamic>> save(Map<String, dynamic> command) async => _workspace(await _rpc('save_line_import_draft', command));
  Future<Map<String, dynamic>> invoicePreview(String draftId, int revision) async {
    final value = await _rpc('line_invoice_preview', {'p_draft_id': draftId, 'p_revision': revision});
    if (value is! Map || value['quotes'] is! List || value['fingerprint'] is! String) throw StateError('請求金額を確認できません。');
    return Map<String, dynamic>.from(value);
  }
  Future<Map<String, dynamic>> formal(String target, Map<String, dynamic> command) async {
    final value = await _rpc(target == 'attendance' ? 'submit_line_attendance' : 'create_line_invoices', command);
    if (value is! Map || (target == 'attendance' ? value['request_id'] is! String || value['item_count'] is! int : value['invoices'] is! List)) throw StateError('登録結果を確認できません。');
    return Map<String, dynamic>.from(value);
  }
  Future<List<Map<String, dynamic>>> sources(String groupId) async {
    final captured = actor;
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 1000) {
      final rows = await client.from('chat_messages').select('id, body, sent_at, sender_display_name')
          .eq('communication_group_id', groupId).eq('origin', 'line').order('sent_at').order('id').range(offset, offset + 999);
      if (client.auth.currentUser?.id != captured) throw StateError('ログインが変わりました。');
      result.addAll(rows.map((row) => <String, dynamic>{...row, 'source_type': 'received'}));
      if (rows.length < 1000) break;
    }
    return result;
  }
  Future<({List<Map<String, dynamic>> workers, List<Map<String, dynamic>> sites})> references(String groupId) async {
    final captured = actor;
    final group = await client.from('communication_groups').select('company_id').eq('id', groupId).single();
    final cid = group['company_id'];
    final workers = await client.from('workers').select('id,name').eq('company_id', cid).eq('status','active').order('name');
    final sites = await client.from('sites').select('id,name,customer_id').eq('company_id', cid).order('name');
    if (client.auth.currentUser?.id != captured) throw StateError('ログインが変わりました。');
    return (workers: List<Map<String, dynamic>>.from(workers), sites: List<Map<String, dynamic>>.from(sites));
  }
}
