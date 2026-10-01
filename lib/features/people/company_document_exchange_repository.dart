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
    final values = await Future.wait([
      _client.rpc(
        'company_document_exchange',
        params: {
          'p_action': 'sources',
          'p_data': <String, dynamic>{},
        },
      ),
      _client.rpc('company_signature_sources'),
    ]);
    final result = <Map<String, dynamic>>[];
    for (final value in values) {
      if (value is! List) continue;
      result.addAll(
        value.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
      );
    }
    return result;
  }

  Future<void> saveReceivedDelivery(String deliveryId) async {
    if (deliveryId.isEmpty) return;
    await _client.rpc(
      'save_received_delivery',
      params: {'p_delivery_id': deliveryId},
    );
  }

  Future<String?> signedDeliveryFileUrl({
    required String bucket,
    required String path,
  }) async {
    if (bucket.isEmpty || path.isEmpty) return null;
    return _client.storage.from(bucket).createSignedUrl(path, 3600);
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

  Future<Map<String, DateTime>> loadSavedDeliveryState() async {
    final value = await _client.rpc('company_delivery_saved_state');
    if (value is! List) return const {};
    final result = <String, DateTime>{};
    for (final raw in value) {
      if (raw is! Map) continue;
      final key = raw['item_key']?.toString() ?? '';
      final savedAt = DateTime.tryParse(raw['saved_at']?.toString() ?? '');
      if (key.isNotEmpty && savedAt != null) {
        result[key] = savedAt.toLocal();
      }
    }
    return result;
  }

  Future<void> saveDeliveryItems(Iterable<String> itemKeys) async {
    final keys =
        itemKeys.where((key) => key.isNotEmpty).toList(growable: false);
    if (keys.isEmpty) return;
    await _client.rpc(
      'save_company_delivery_items',
      params: {'p_item_keys': keys},
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
    final signatureItems = items
        .where((item) => item['kind'] == 'daily_report_signature')
        .toList(growable: false);
    if (signatureItems.isNotEmpty) {
      if (signatureItems.length != items.length) {
        throw StateError('サイン一覧と他データは分けて送信してください。');
      }
      final value = await _client.rpc(
        'send_connected_signature_data',
        params: {
          'p_request_id': requestId,
          'p_target_company_id': targetCompanyId,
          'p_report_ids': [
            for (final item in signatureItems) item['id']?.toString(),
          ],
          'p_note': note.trim(),
        },
      );
      return value?.toString() ?? requestId;
    }

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
