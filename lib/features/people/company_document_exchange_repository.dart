import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/authenticated_storage_download.dart';
import '../../data/supabase_backend.dart';

class CompanyDocumentExchangeRepository {
  CompanyDocumentExchangeRepository._(this._client);
  @visibleForTesting CompanyDocumentExchangeRepository.forTesting(this._client);

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

  Future<List<Map<String, dynamic>>> listSignatureSources() async {
    final value = await _client.rpc('company_signature_sources');
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
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

  Future<Uint8List> downloadDeliveryFile({
    required String deliveryId,
    required String itemId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw StateError('ログイン状態を確認してください。');
    }
    final items = await listDeliveryItems(deliveryId);
    final item = items.singleWhere((row) => row['id'] == itemId);
    final bucket = item['bucket'];
    final path = item['path'];
    if (bucket is! String || bucket.isEmpty || path is! String || path.isEmpty ||
        _client.auth.currentSession?.accessToken != session.accessToken) {
      throw StateError('書類の閲覧権限を確認できません。');
    }
    return downloadAuthenticatedStorageObject(_client, bucket: bucket, path: path);
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

  Future<Map<String, String>> employmentContractIssuer(String itemId) async {
    final session = _client.auth.currentSession;
    if (session == null) throw StateError('ログイン状態を確認してください。');
    final token = session.accessToken;
    final workerId = await _client.rpc(
      'resolve_partner_allowance_worker', params: {'p_item_id': itemId},
    ).setHeader('Authorization', 'Bearer $token');
    if (workerId is! String) throw StateError('給与対象を確認できません。');
    final worker = await _client.from('workers').select('company_id')
        .eq('id', workerId).single()
        .setHeader('Authorization', 'Bearer $token');
    final companyId = worker['company_id'];
    final company = await _client.from('companies')
        .select('id, name, postal_code, address, phone')
        .eq('id', companyId).single()
        .setHeader('Authorization', 'Bearer $token');
    final profile = await _client.rpc(
      'read_partner_company_profile', params: {'p_company_id': companyId},
    ).setHeader('Authorization', 'Bearer $token');
    if (_client.auth.currentSession?.accessToken != token ||
        profile is! Map || profile['company_id'] != companyId ||
        profile['profile'] is! Map || profile['profile']['name'] != company['name']) {
      throw StateError('発行元の会社情報を確認できません。');
    }
    return {
      for (final key in ['name', 'postal_code', 'address', 'phone'])
        key: company[key]?.toString().trim() ?? '',
      'representative_name':
          profile['profile']['representative_name']?.toString().trim() ?? '',
    };
  }

  Future<String?> resolvePartnerAllowanceWorker(String itemId) async {
    final value = await _client.rpc(
      'resolve_partner_allowance_worker',
      params: {'p_item_id': itemId},
    );
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<Map<String, dynamic>?> partnerEmploymentContractDraft(
    String itemId, {
    Map<String, dynamic>? document,
    int? revision,
  }) async {
    final value = await _client.rpc(
      'partner_employment_contract_draft',
      params: {
        'p_item_id': itemId,
        'p_document': document,
        'p_revision': revision,
      },
    );
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<void> approvePartnerEmploymentContract(
    String itemId, int revision, DateTime month,
  ) async {
    final year = month.year.toString().padLeft(4, '0');
    final number = month.month.toString().padLeft(2, '0');
    await _client.rpc('approve_partner_employment_contract', params: {
      'p_item_id': itemId,
      'p_revision': revision,
      'p_month': '$year-$number-01',
    });
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
    Future<void> Function()? beforeWrite,
  }) async {
    final signatureItems = items
        .where((item) => item['kind'] == 'daily_report_signature')
        .toList(growable: false);
    if (signatureItems.isNotEmpty) {
      if (signatureItems.length != items.length) {
        throw StateError('サイン一覧と他データは分けて送信してください。');
      }
      await beforeWrite?.call();
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

    await beforeWrite?.call();
    final code = await _client.rpc(
      'connected_parent_receive_code',
      params: {'p_parent_company_id': targetCompanyId},
    );
    final receiveCode = code?.toString() ?? '';
    if (receiveCode.isEmpty) {
      throw StateError('接続済み会社への送信準備に失敗しました。');
    }
    await beforeWrite?.call();
    final deliveryId = await send(
      requestId: requestId,
      receiveCode: receiveCode,
      items: items,
      note: note,
    );

    final personnelWorkerIds = items
        .where((item) => item['kind'] == 'worker_personnel')
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (personnelWorkerIds.isNotEmpty) {
      try {
      await beforeWrite?.call();
      await _client.rpc(
        'append_employee_personnel_details',
        params: {
          'p_delivery_id': deliveryId,
          'p_worker_ids': personnelWorkerIds,
        },
      );
      } catch(error) {
        if(beforeWrite==null)rethrow;
        throw StateError('基本データは送信済みですが、個人情報の追加を完了できませんでした。再送せず送信履歴を確認してください。');
      }
    }

    return deliveryId;
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
