import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class HomeIdentity {
  const HomeIdentity({
    required this.role,
    required this.companyName,
    required this.displayName,
    this.permissions = const {},
  });

  final String role;
  final String companyName;
  final String displayName;
  final Map<String, bool> permissions;

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isSubAdmin => role == 'manager';
  bool get isManagement => isAdmin || isSubAdmin;

  bool can(String key) {
    if (key == 'can_approve_daily_report_edits') {
      return permissions[key] ?? false;
    }
    if (role == 'owner' || role == 'admin') return true;
    return permissions[key] ?? false;
  }

  String get roleLabel => switch (role) {
        'owner' => '管理者',
        'admin' => '管理者',
        'manager' => 'サブ管理者',
        _ => '一般ユーザー',
      };
}

class HomeMembershipRepository {
  HomeMembershipRepository._(this._client);

  final SupabaseClient _client;

  static HomeMembershipRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return HomeMembershipRepository._(client);
  }

  Future<String> loadRole() async => (await loadIdentity()).role;

  Future<HomeIdentity> loadIdentity() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const HomeIdentity(
        role: 'viewer',
        companyName: 'SKO',
        displayName: 'ユーザー',
        permissions: {},
      );
    }

    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) {
      return HomeIdentity(
        role: 'viewer',
        companyName: 'SKO',
        displayName: user.phone ?? user.email ?? 'ユーザー',
        permissions: const {},
      );
    }

    final companyId = rows.first['company_id'] as String;
    final role = rows.first['role']?.toString() ?? 'viewer';

    final values = await Future.wait([
      _client
          .from('companies')
          .select('name')
          .eq('id', companyId)
          .limit(1),
      _client
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .limit(1),
    ]);

    final companies = values[0] as List<dynamic>;
    final profiles = values[1] as List<dynamic>;

    final permissions = <String, bool>{};

    try {
      final permissionValue =
          await _client.rpc('current_feature_permissions');
      if (permissionValue is Map) {
        for (final entry in permissionValue.entries) {
          permissions[entry.key.toString()] = entry.value == true;
        }
      }
    } catch (_) {
      // Keep identity loading available even if optional permissions are absent.
    }

    try {
      final payrollAdjustmentPermissionValue =
          await _client.rpc('current_payroll_adjustment_permissions');
      if (payrollAdjustmentPermissionValue is Map) {
        permissions['can_view_payroll_adjustments'] =
            payrollAdjustmentPermissionValue['can_view'] == true;
        permissions['can_manage_payroll_adjustments'] =
            payrollAdjustmentPermissionValue['can_manage'] == true;
      }
    } catch (_) {
      // Payroll adjustment permissions are optional during rollout.
    }

    final companyName = companies.isNotEmpty
        ? (companies.first['name']?.toString() ?? 'SKO')
        : 'SKO';
    final displayName = profiles.isNotEmpty &&
            (profiles.first['display_name']?.toString().trim().isNotEmpty ??
                false)
        ? profiles.first['display_name'].toString()
        : user.phone ?? user.email ?? 'ユーザー';

    return HomeIdentity(
      role: role,
      companyName: companyName,
      displayName: displayName,
      permissions: permissions,
    );
  }
}
