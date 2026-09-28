import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class MemberPermissionRecord {
  const MemberPermissionRecord({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.permissions,
  });

  final String userId;
  final String displayName;
  final String role;
  final Map<String, bool> permissions;

  MemberPermissionRecord copyWith({
    String? role,
    Map<String, bool>? permissions,
  }) {
    return MemberPermissionRecord(
      userId: userId,
      displayName: displayName,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
    );
  }
}

class ApprovalAssigneeRecord {
  const ApprovalAssigneeRecord({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.isAssignee,
  });

  final String userId;
  final String displayName;
  final String role;
  final bool isAssignee;
}

class MemberPermissionRepository {
  MemberPermissionRepository._(this._client);

  final SupabaseClient _client;

  static MemberPermissionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return MemberPermissionRepository._(client);
  }

  Future<List<MemberPermissionRecord>> loadAll() async {
    final values = await Future.wait([
      _client.rpc('company_member_permission_rows'),
      _client.rpc('company_payroll_adjustment_permission_rows'),
    ]);

    final rows = values[0] as List<dynamic>;
    final adjustmentRows = values[1] as List<dynamic>;
    final adjustmentsByUser = <String, Map<String, dynamic>>{
      for (final raw in adjustmentRows)
        if ((raw as Map)['user_id'] != null)
          raw['user_id'].toString(): Map<String, dynamic>.from(raw),
    };

    final records = <MemberPermissionRecord>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final userId = row['user_id']?.toString() ?? '';
      final adjustment = adjustmentsByUser[userId] ?? const <String, dynamic>{};

      records.add(
        MemberPermissionRecord(
          userId: userId,
          displayName: row['display_name']?.toString() ?? 'SKOユーザー',
          role: row['role']?.toString() ?? 'viewer',
          permissions: {
            'can_approve_daily_report_edits':
                row['can_approve_daily_report_edits'] == true,
            'can_manage_attendance': row['can_manage_attendance'] == true,
            'can_manage_people': row['can_manage_people'] == true,
            'can_view_invoices': row['can_view_invoices'] == true,
            'can_manage_invoices': row['can_manage_invoices'] == true,
            'can_view_admin_site_data':
                row['can_view_admin_site_data'] == true,
            'can_manage_admin_site_data':
                row['can_manage_admin_site_data'] == true,
            'can_manage_payroll': row['can_manage_payroll'] == true,
            'can_manage_partner_chat': row['can_manage_partner_chat'] == true,
            'can_view_payroll_adjustments':
                adjustment['can_view'] == true,
            'can_manage_payroll_adjustments':
                adjustment['can_manage'] == true,
          },
        ),
      );
    }

    return records;
  }

  Future<List<ApprovalAssigneeRecord>> loadApprovalAssignees() async {
    final rows = await _client.rpc('company_approval_assignee_rows');
    return [
      for (final raw in (rows as List<dynamic>))
        ApprovalAssigneeRecord(
          userId: (raw as Map)['user_id']?.toString() ?? '',
          displayName: raw['display_name']?.toString() ?? 'SKOユーザー',
          role: raw['role']?.toString() ?? 'manager',
          isAssignee: raw['is_assignee'] == true,
        ),
    ];
  }

  Future<void> setApprovalAssignee({
    required String userId,
    required bool enabled,
  }) async {
    await _client.rpc(
      'set_company_approval_assignee',
      params: {
        'p_user_id': userId,
        'p_enabled': enabled,
      },
    );
  }

  Future<void> save(MemberPermissionRecord record) async {
    await _client.rpc(
      'set_member_feature_permissions',
      params: {
        'p_user_id': record.userId,
        'p_role': record.role,
        'p_permissions': record.permissions,
      },
    );

    if (record.role != 'admin') {
      await _client.rpc(
        'set_payroll_adjustment_permissions',
        params: {
          'p_user_id': record.userId,
          'p_can_view':
              record.permissions['can_view_payroll_adjustments'] ?? false,
          'p_can_manage':
              record.permissions['can_manage_payroll_adjustments'] ?? false,
        },
      );
    }
  }
}
