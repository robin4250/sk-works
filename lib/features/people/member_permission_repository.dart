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
    final rows = await _client.rpc('company_member_permission_rows');
    final records = <MemberPermissionRecord>[];

    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      records.add(
        MemberPermissionRecord(
          userId: row['user_id']?.toString() ?? '',
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
          },
        ),
      );
    }

    return records;
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
  }
}
