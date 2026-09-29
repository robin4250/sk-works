import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CompanyDocumentExchangeItem {
  const CompanyDocumentExchangeItem({
    required this.id,
    required this.kind,
    required this.name,
    this.group,
  });

  final String id;
  final String kind;
  final String name;
  final String? group;

  Map<String, String> toSendJson() => {
        'id': id,
        'kind': kind,
      };

  factory CompanyDocumentExchangeItem.fromJson(Map<String, dynamic> json) {
    return CompanyDocumentExchangeItem(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString(),
    );
  }
}

class CompanyDocumentExchangeRepository {
  CompanyDocumentExchangeRepository._(this._client);

  final SupabaseClient _client;

  static CompanyDocumentExchangeRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return CompanyDocumentExchangeRepository._(client);
  }

  Future<Map<String, dynamic>> issueReceiveCode() async {
    final value = await _rpc('issue');
    return Map<String, dynamic>.from(value);
  }

  Future<String> resolveReceiveCode(String code) async {
    final value = await _rpc('resolve', {'code': code.trim()});
    return value['company_name']?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> listDeliveries() async {
    final value = await _rpc('list');
    return _mapList(value);
  }

  Future<List<Map<String, dynamic>>> listDeliveryItems(String deliveryId) async {
    final value = await _rpc('items', {'id': deliveryId});
    return _mapList(value);
  }

  Future<List<CompanyDocumentExchangeItem>> listSources() async {
    final value = await _rpc('sources');
    return [
      for (final row in _mapList(value))
        CompanyDocumentExchangeItem.fromJson(row),
    ];
  }

  Future<String> send({
    required String receiveCode,
    required List<CompanyDocumentExchangeItem> items,
    String note = '',
    String? requestId,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', '送信する書類を選択してください。');
    }

    final value = await _rpc(
      'send',
      {
        'request_id': requestId ?? createRequestId(),
        'code': receiveCode.trim(),
        'items': [for (final item in items) item.toSendJson()],
        'note': note.trim(),
      },
    );
    return value['id']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> _rpc(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    final raw = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': action,
        'p_data': data,
      },
    );
    if (raw is! Map) {
      throw StateError('会社間書類データの応答を確認できません。');
    }
    return Map<String, dynamic>.from(raw);
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  static String createRequestId([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
