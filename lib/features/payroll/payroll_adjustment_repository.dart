import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PayrollAdjustmentAccess {
  const PayrollAdjustmentAccess({
    required this.pageLabel,
    required this.canView,
    required this.canManage,
    required this.canRename,
  });

  final String pageLabel;
  final bool canView;
  final bool canManage;
  final bool canRename;
}

class PayrollAdjustmentWorker {
  const PayrollAdjustmentWorker({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class PayrollAdjustmentTypeOption {
  const PayrollAdjustmentTypeOption({
    required this.id,
    required this.label,
    required this.direction,
    required this.isActive,
  });

  final String id;
  final String label;
  final String direction;
  final bool isActive;

  bool get isAddition => direction == 'addition';
}

class PayrollAdjustmentListItem {
  const PayrollAdjustmentListItem({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.typeId,
    required this.label,
    required this.direction,
    required this.amountYen,
    required this.effectiveDate,
    required this.createdAt,
    this.note,
    this.cancelledAt,
    this.cancellationReason,
  });

  final String id;
  final String workerId;
  final String workerName;
  final String typeId;
  final String label;
  final String direction;
  final int amountYen;
  final DateTime effectiveDate;
  final DateTime createdAt;
  final String? note;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  bool get isAddition => direction == 'addition';
  bool get isCancelled => cancelledAt != null;
  int get signedAmountYen => isCancelled ? 0 : (isAddition ? amountYen : -amountYen);
}

class PayrollAdjustmentRepository {
  PayrollAdjustmentRepository._(this._client);

  final SupabaseClient _client;

  static PayrollAdjustmentRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PayrollAdjustmentRepository._(client);
  }

  Future<PayrollAdjustmentAccess> loadAccess() async {
    final raw = await _client.rpc('payroll_adjustment_access');
    final value = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return PayrollAdjustmentAccess(
      pageLabel: (value['page_label']?.toString().trim().isNotEmpty ?? false)
          ? value['page_label'].toString().trim()
          : '給与調整',
      canView: value['can_view'] == true,
      canManage: value['can_manage'] == true,
      canRename: value['can_rename'] == true,
    );
  }

  Future<List<PayrollAdjustmentWorker>> loadWorkers() async {
    final rows = await _client.rpc('payroll_adjustment_worker_rows');
    return [
      for (final raw in (rows as List<dynamic>))
        PayrollAdjustmentWorker(
          id: (raw as Map)['worker_id']?.toString() ?? '',
          name: raw['worker_name']?.toString() ?? '',
        ),
    ].where((item) => item.id.isNotEmpty && item.name.isNotEmpty).toList();
  }

  Future<List<PayrollAdjustmentTypeOption>> loadTypes() async {
    final rows = await _client.rpc('payroll_adjustment_type_rows');
    return [
      for (final raw in (rows as List<dynamic>))
        PayrollAdjustmentTypeOption(
          id: (raw as Map)['id']?.toString() ?? '',
          label: raw['label']?.toString() ?? '',
          direction: raw['direction']?.toString() ?? 'deduction',
          isActive: raw['is_active'] == true,
        ),
    ].where((item) => item.id.isNotEmpty && item.label.isNotEmpty).toList();
  }

  Future<List<PayrollAdjustmentListItem>> loadAdjustments({
    String? workerId,
    DateTime? start,
    DateTime? end,
  }) async {
    String? date(DateTime? value) {
      if (value == null) return null;
      return value.toIso8601String().substring(0, 10);
    }

    final rows = await _client.rpc(
      'payroll_adjustment_rows',
      params: {
        'p_worker_id': workerId,
        'p_start': date(start),
        'p_end': date(end),
      },
    );

    return [
      for (final raw in (rows as List<dynamic>))
        PayrollAdjustmentListItem(
          id: (raw as Map)['id']?.toString() ?? '',
          workerId: raw['worker_id']?.toString() ?? '',
          workerName: raw['worker_name']?.toString() ?? '',
          typeId: raw['type_id']?.toString() ?? '',
          label: raw['label']?.toString() ?? '',
          direction: raw['direction']?.toString() ?? 'deduction',
          amountYen: (raw['amount_yen'] as num?)?.toInt() ?? 0,
          effectiveDate:
              DateTime.tryParse(raw['effective_date']?.toString() ?? '') ??
                  DateTime.now(),
          createdAt: DateTime.tryParse(raw['created_at']?.toString() ?? '') ??
              DateTime.now(),
          note: raw['note']?.toString(),
          cancelledAt:
              DateTime.tryParse(raw['cancelled_at']?.toString() ?? ''),
          cancellationReason: raw['cancellation_reason']?.toString(),
        ),
    ].where((item) => item.id.isNotEmpty).toList();
  }

  Future<void> setPageLabel(String label) async {
    await _client.rpc(
      'set_payroll_adjustment_page_label',
      params: {'p_label': label.trim()},
    );
  }

  Future<String> saveType({
    String? id,
    required String label,
    required String direction,
    bool isActive = true,
  }) async {
    final raw = await _client.rpc(
      'upsert_payroll_adjustment_type',
      params: {
        'p_id': id,
        'p_label': label.trim(),
        'p_direction': direction,
        'p_is_active': isActive,
      },
    );
    return raw?.toString() ?? '';
  }

  Future<String> createAdjustment({
    required String workerId,
    required String typeId,
    required int amountYen,
    required DateTime effectiveDate,
    String? note,
  }) async {
    final raw = await _client.rpc(
      'create_payroll_adjustment',
      params: {
        'p_worker_id': workerId,
        'p_type_id': typeId,
        'p_amount_yen': amountYen,
        'p_effective_date': effectiveDate.toIso8601String().substring(0, 10),
        'p_note': note?.trim(),
      },
    );
    return raw?.toString() ?? '';
  }

  Future<void> updateAdjustment({
    required String id,
    required String typeId,
    required int amountYen,
    required DateTime effectiveDate,
    String? note,
  }) async {
    await _client.rpc(
      'update_payroll_adjustment',
      params: {
        'p_id': id,
        'p_type_id': typeId,
        'p_amount_yen': amountYen,
        'p_effective_date': effectiveDate.toIso8601String().substring(0, 10),
        'p_note': note?.trim(),
      },
    );
  }

  Future<void> cancelAdjustment({
    required String id,
    String? reason,
  }) async {
    await _client.rpc(
      'cancel_payroll_adjustment',
      params: {
        'p_id': id,
        'p_reason': reason?.trim(),
      },
    );
  }
}
