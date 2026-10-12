import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class RouteBillingQuantityRequest {
  RouteBillingQuantityRequest(this.raw);
  final Map<String, dynamic> raw;
  String get id => raw['id']?.toString() ?? '';
  String get workerName => raw['worker_name']?.toString() ?? '';
  String get customerName => raw['customer_name']?.toString() ?? '';
  String get workDate => raw['work_date']?.toString() ?? '';
  String get status => raw['status']?.toString() ?? '';
  int get version => (raw['version'] as num?)?.toInt() ?? 0;
  double? get quantity => (raw['quantity'] as num?)?.toDouble();
  List<Map<String, dynamic>> get siteOptions => [
    for (final item
        in raw['site_options'] is List ? raw['site_options'] as List : [])
      if (item is Map && item['man_day_method'] == true)
        Map<String, dynamic>.from(item),
  ];
  List<Map<String, dynamic>> get evidence => [
    for (final item in raw['evidence'] is List ? raw['evidence'] as List : [])
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

class RouteBillingQuantityApprovalRepository {
  RouteBillingQuantityApprovalRepository._(this._client);
  factory RouteBillingQuantityApprovalRepository.forTesting(
    SupabaseClient client,
  ) => RouteBillingQuantityApprovalRepository._(client);
  final SupabaseClient _client;
  static RouteBillingQuantityApprovalRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    return client.auth.currentUser == null
        ? null
        : RouteBillingQuantityApprovalRepository._(client);
  }

  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) {
      throw StateError('ログイン情報を確認してください');
    }
    final result = await _client.rpc(name, params: params);
    if (_client.auth.currentUser?.id != actor) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください');
    }
    return result;
  }

  Future<List<RouteBillingQuantityRequest>> pending() async {
    final result = await _rpc('pending_route_billing_quantity_rows', {});
    if (result is! List) {
      throw StateError('請求数量の承認待ちを確認できません');
    }
    return [
      for (final row in result)
        if (row is Map)
          RouteBillingQuantityRequest(Map<String, dynamic>.from(row)),
    ].where((row) => row.id.isNotEmpty).toList();
  }

  Future<RouteBillingQuantityRequest> detail(String id) async {
    final result = await _rpc('route_billing_quantity_request_detail', {
      'p_request_id': id,
    });
    if (result is! Map || result['id'] != id) {
      throw StateError('対象の請求数量を確認できません');
    }
    return RouteBillingQuantityRequest(Map<String, dynamic>.from(result));
  }

  Future<String> decide({
    required RouteBillingQuantityRequest request,
    required bool approve,
    required double quantity,
    String? siteId,
    int? unitPriceYen,
    String? note,
  }) async {
    if (request.raw['version'] is! int || request.version < 1) {
      throw StateError('請求数量の更新状態を確認できません。再読み込みしてください');
    }
    if (quantity != 1 && quantity != 0.5) {
      throw ArgumentError.value(quantity);
    }
    if (approve &&
        (siteId == null ||
            siteId.isEmpty ||
            unitPriceYen == null ||
            unitPriceYen <= 0)) {
      throw StateError('請求に使用する現場と単価を選択してください');
    }
    final result = await _rpc('decide_route_billing_quantity', {
      'p_request_id': request.id,
      'p_quantity': quantity,
      'p_decision': approve ? 'approve' : 'reject',
      'p_note': note?.trim(),
      'p_expected_version': request.version,
      'p_representative_site_id': siteId,
      'p_unit_price_yen': unitPriceYen,
    });
    if (result is! Map ||
        result['id'] != request.id ||
        result['status'] != (approve ? 'approved' : 'rejected')) {
      throw StateError('処理結果を確認できません。再読み込みしてください');
    }
    return result['status'].toString();
  }
}
