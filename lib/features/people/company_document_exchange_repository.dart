import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

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
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'issue',
        'p_data': <String, dynamic>{},
      },
    );
    return Map<String, dynamic>.from(value as Map);
  }

  Future<Map<String, dynamic>> resolveReceiveCode(String code) async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'resolve',
        'p_data': {'code': code.trim()},
      },
    );
    return Map<String, dynamic>.from(value as Map);
  }

  Future<List<Map<String, dynamic>>> listDeliveries() async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'list',
        'p_data': <String, dynamic>{},
      },
    );
    return [
      for (final item in value as List<dynamic>)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listDeliveryItems(String deliveryId) async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'items',
        'p_data': {'id': deliveryId},
      },
    );
    return [
      for (final item in value as List<dynamic>)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listDeliveryDataItems(
    String deliveryId,
  ) async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'data_items',
        'p_data': {'id': deliveryId},
      },
    );
    return [
      for (final item in value as List<dynamic>)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<List<Map<String, dynamic>>> listSendableSources() async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'sources',
        'p_data': <String, dynamic>{},
      },
    );
    return [
      for (final item in value as List<dynamic>)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<Map<String, dynamic>> loadConnectionInbox() async {
    final value = await _client.rpc('company_connection_inbox');
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  Future<void> respondCompanyConnection({
    required String connectionId,
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_company_connection',
      params: {
        'p_connection_id': connectionId,
        'p_accept': accept,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listTransferTargets() async {
    final value = await _client.rpc('company_connection_targets');
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<String> sendConnected({
    required String requestId,
    required String targetCompanyId,
    required List<Map<String, dynamic>> items,
    String note = '',
  }) async {
    final code = await _client.rpc(
      'connected_parent_receive_code',
      params: {'p_parent_company_id': targetCompanyId},
    );
    final receiveCode = code?.toString() ?? '';
    if (receiveCode.isEmpty) {
      throw StateError('接続済み会社への送信準備に失敗しました。');
    }
    return send(
      requestId: requestId,
      receiveCode: receiveCode,
      items: items,
      note: note,
    );
  }

  Future<String> send({
    required String requestId,
    required String receiveCode,
    required List<Map<String, dynamic>> items,
    String note = '',
  }) async {
    final value = await _client.rpc(
      'company_document_exchange',
      params: {
        'p_action': 'send',
        'p_data': {
          'request_id': requestId,
          'code': receiveCode.trim(),
          'items': items,
          'note': note.trim(),
        },
      },
    );
    final row = Map<String, dynamic>.from(value as Map);
    return row['id']?.toString() ?? requestId;
  }
}
