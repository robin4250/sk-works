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
