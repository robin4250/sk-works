import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

class RouteCustomerQuantityCandidate {
  const RouteCustomerQuantityCandidate({required this.id, required this.name,
    required this.reportIds, required this.sites, required this.version,
    this.requestedQuantity, this.approvedQuantity, this.status});
  final String id, name;
  final List<String> reportIds, sites;
  final int version;
  final double? requestedQuantity, approvedQuantity;
  final String? status;
}

class RouteCustomerQuantityDay {
  const RouteCustomerQuantityDay(this.customers, this.unresolvedCount);
  final List<RouteCustomerQuantityCandidate> customers;
  final int unresolvedCount;
}

abstract class RouteCustomerQuantityAccess {
  String get actor;
  void checkActor(String captured);
  Future<RouteCustomerQuantityDay> load(String workerId, DateTime date);
  Future<void> submit(String workerId, DateTime date, RouteCustomerQuantityDay day,
    Map<String, double> quantities);
}

class RouteCustomerDayQuantityRepository implements RouteCustomerQuantityAccess {
  RouteCustomerDayQuantityRepository(this.client);
  final SupabaseClient client;
  static RouteCustomerDayQuantityRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
      ? RouteCustomerDayQuantityRepository(SupabaseBackend.client) : null;
  @override
  String get actor => client.auth.currentUser?.id ?? (throw StateError('ログインを確認してください。'));
  @override
  void checkActor(String captured) {
    if (client.auth.currentUser?.id != captured) {
      throw StateError('ログインが変更されました。画面を開き直してください。');
    }
  }
  String _date(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    final captured = actor;
    final result = await client.rpc(name, params: params);
    checkActor(captured);
    return result;
  }
  @override
  Future<RouteCustomerQuantityDay> load(String workerId, DateTime date) async {
    final value = await _rpc('route_customer_day_quantity_candidates', {
      'p_worker_id': workerId, 'p_work_date': _date(date),
    });
    if (value is! Map || value['customers'] is! List || value['unresolved_count'] is! num) {
      throw StateError('請求数量の対象を確認できません。');
    }
    final candidates = <RouteCustomerQuantityCandidate>[];
    for (final row in value['customers'] as List) {
      if (row is! Map || row['customer_id'] is! String || row['customer_name'] is! String ||
          row['version'] is! int || row['report_ids'] is! List || row['visits'] is! List) {
        throw StateError('保存済み訪問情報を確認できません。');
      }
      final ids = (row['report_ids'] as List).cast<String>();
      if (ids.isEmpty || ids.any((id) => id.isEmpty)) {
        throw StateError('日報の識別情報を確認できません。');
      }
      candidates.add(RouteCustomerQuantityCandidate(id: row['customer_id'] as String,
        name: row['customer_name'] as String, reportIds: ids,
        sites: [for (final visit in row['visits'] as List)
          if (visit is Map && visit['site_name'] is String) visit['site_name'] as String],
        version: row['version'] as int,
        requestedQuantity: (row['requested_quantity'] as num?)?.toDouble(),
        approvedQuantity: row['status'] == 'approved' ? (row['quantity'] as num?)?.toDouble() : null,
        status: row['status']?.toString()));
    }
    return RouteCustomerQuantityDay(candidates, (value['unresolved_count'] as num).toInt());
  }
  @override
  Future<void> submit(String workerId, DateTime date, RouteCustomerQuantityDay day,
    Map<String, double> quantities) async {
    if (day.unresolvedCount != 0 || day.customers.isEmpty ||
        quantities.length != day.customers.length || day.customers.any((c) =>
          quantities[c.id] != 1 && quantities[c.id] != 0.5)) {
      throw StateError('すべての取引会社の数量を選択してください。');
    }
    final value = await _rpc('submit_route_customer_day_allocations_checked', {
      'p_worker_id': workerId, 'p_work_date': _date(date),
      'p_report_ids': [for (final c in day.customers) ...c.reportIds],
      'p_allocations': [for (final c in day.customers)
        {'customer_id': c.id, 'quantity': quantities[c.id]}],
      'p_expected_versions': {for (final c in day.customers) c.id: c.version},
    });
    if (value is! List || value.length != day.customers.length || value.any((row) =>
      row is! Map || !day.customers.any((c) => c.id == row['customer_id']) ||
      !['pending', 'approved', 'rejected'].contains(row['status'])) ||
      value.whereType<Map>().map((row) => row['customer_id']).toSet().length != day.customers.length) {
      throw StateError('申請結果を確認できません。再読み込みしてください。');
    }
  }
}
