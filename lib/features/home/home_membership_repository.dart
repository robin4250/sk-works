import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class HomeIdentity {
  const HomeIdentity({
    required this.role,
    required this.companyName,
    required this.displayName,
    this.permissions = const {},
    this.isMasterAdmin = false,
  });

  final String role;
  final String companyName;
  final String displayName;
  final Map<String, bool> permissions;
  final bool isMasterAdmin;

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isSubAdmin => role == 'manager';
  bool get isManagement => isMasterAdmin || isAdmin || isSubAdmin;

  bool can(String key) {
    if (key == 'can_approve_daily_report_edits') {
      return permissions[key] ?? false;
    }
    if (role == 'owner' || role == 'admin') return true;
    return permissions[key] ?? false;
  }

  String get roleLabel {
    if (isMasterAdmin) return 'Master';
    return switch (role) {
      'owner' => '管理者',
      'admin' => '管理者',
      'manager' => 'サブ管理者',
      _ => '一般ユーザー',
    };
  }
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

    var isMasterAdmin = false;
    try {
      final masterStatus = await _client.rpc('current_master_admin_status');
      if (masterStatus is Map) {
        isMasterAdmin = masterStatus['is_master_admin'] == true;
      }
    } catch (_) {
      // Master status is independent from company membership resolution.
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
        isMasterAdmin: isMasterAdmin,
      );
    }

    // Membership role is authoritative. Once it is loaded, optional home
    // enrichment must never downgrade owner/admin/manager to viewer.
    final companyId = rows.first['company_id'] as String;
    final role = rows.first['role']?.toString() ?? 'viewer';

    List<dynamic> companies = const [];
    try {
      companies = await _client
          .from('companies')
          .select('name')
          .eq('id', companyId)
          .limit(1);
    } catch (_) {
      // Company display data is optional for role resolution.
    }

    List<dynamic> profiles = const [];
    try {
      profiles = await _client
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .limit(1);
    } catch (_) {
      // Profile display data is optional for role resolution.
    }

    dynamic permissionValue;
    try {
      permissionValue = await _client.rpc('current_feature_permissions');
    } catch (_) {
      // Feature permission enrichment must not erase the membership role.
    }

    dynamic payrollAdjustmentPermissionValue;
    try {
      payrollAdjustmentPermissionValue =
          await _client.rpc('current_payroll_adjustment_permissions');
    } catch (_) {
      // Payroll permission enrichment must not erase the membership role.
    }

    final permissions = <String, bool>{
      if (permissionValue is Map)
        for (final entry in permissionValue.entries)
          entry.key.toString(): entry.value == true,
      if (payrollAdjustmentPermissionValue is Map) ...{
        'can_view_payroll_adjustments':
            payrollAdjustmentPermissionValue['can_view'] == true,
        'can_manage_payroll_adjustments':
            payrollAdjustmentPermissionValue['can_manage'] == true,
      },
    };

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
      isMasterAdmin: isMasterAdmin,
    );
  }
}
