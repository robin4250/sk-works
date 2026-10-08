import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class IndividualPayrollWorker {
  const IndividualPayrollWorker({required this.id, required this.name});
  final String id;
  final String name;
}

class IndividualPayrollWorkspace {
  const IndividualPayrollWorkspace({
    required this.canView,
    required this.canEdit,
    required this.isAdmin,
    required this.workers,
  });

  final bool canView;
  final bool canEdit;
  final bool isAdmin;
  final List<IndividualPayrollWorker> workers;
}

class IndividualPayrollSetting {
  const IndividualPayrollSetting({
    required this.workerId,
    required this.values,
    this.updatedAt,
  });

  final String workerId;
  final Map<String, dynamic> values;
  final DateTime? updatedAt;

  num amount(String key) => (values[key] as num?) ?? 0;
  String text(String key) => values[key]?.toString() ?? '';
}

class IndividualPayrollSettingsRepository {
  IndividualPayrollSettingsRepository._(this._client);

  final SupabaseClient _client;

  static IndividualPayrollSettingsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return IndividualPayrollSettingsRepository._(client);
  }

  Future<bool> supportsPaidLeaveWages() async {
    try {
      return await _client.rpc('paid_leave_wage_contract_version') == 1;
    } catch (_) {
      // Older servers and failed reads must never be presented as active.
      return false;
    }
  }

  Future<IndividualPayrollWorkspace> loadWorkspace() async {
    final raw = await _client.rpc('payroll_workspace');
    final value =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final permissions = value['permissions'] is Map
        ? Map<String, dynamic>.from(value['permissions'] as Map)
        : const <String, dynamic>{};
    final workersRaw = value['workers'] is List
        ? value['workers'] as List<dynamic>
        : const <dynamic>[];

    return IndividualPayrollWorkspace(
      canView: permissions['view'] == true,
      canEdit: permissions['edit'] == true,
      isAdmin: permissions['admin'] == true,
      workers: [
        for (final rawWorker in workersRaw)
          if (rawWorker is Map)
            IndividualPayrollWorker(
              id: rawWorker['id']?.toString() ?? '',
              name: rawWorker['name']?.toString() ?? '',
            ),
      ].where((item) => item.id.isNotEmpty).toList(growable: false),
    );
  }

  Future<IndividualPayrollSetting> loadSetting(String workerId) async {
    final rows = await _client
        .from('worker_payroll_settings')
        .select()
        .eq('worker_id', workerId)
        .limit(1);
    if (rows.isEmpty) {
      return IndividualPayrollSetting(workerId: workerId, values: const {});
    }
    final row = Map<String, dynamic>.from(rows.first);
    return IndividualPayrollSetting(
      workerId: workerId,
      values: row,
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal(),
    );
  }

  Future<void> saveSetting({
    required String workerId,
    required Map<String, dynamic> values,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です');

    final memberships = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (memberships.isEmpty) throw StateError('会社への所属が必要です');

    final companyId = memberships.first['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw StateError('会社情報を確認できません');
    }

    await _client.from('worker_payroll_settings').upsert(
      {
        'worker_id': workerId,
        'company_id': companyId,
        ...values,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'worker_id',
    );
  }
}
