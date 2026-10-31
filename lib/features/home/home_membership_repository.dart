import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../shared/trade_document_form_session.dart';

class HomeIdentity {
  const HomeIdentity({
    required this.role,
    required this.companyName,
    required this.displayName,
    this.permissions = const {},
    this.companyId,
  });

  final String role;
  final String companyName;
  final String displayName;
  final String? companyId;
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
  HomeMembershipRepository.forClient(this._client);

  final SupabaseClient _client;

  static HomeMembershipRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return HomeMembershipRepository._(client);
  }

  Future<String> loadRole() async => (await loadIdentity()).role;

  Future<HomeIdentity> loadIdentity({String? companyId}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const HomeIdentity(
        role: 'viewer',
        companyName: 'SKO',
        displayName: 'ユーザー',
        permissions: {},
      );
    }

    final captured = _client.auth.currentSession;
    if (captured == null) { throw StateError('ログイン状態を確認してください。'); }
    final lease = TradeDocumentFormSession(_client);
    try {
    await lease.ready();
    final raw = await lease.readOwnMemberships();
    if (raw is! List || raw.any((row) => row is! Map)) { throw StateError('会社を確認できません。'); }
    final rows = raw.whereType<Map>().where((row) => companyId == null || row['company_id'] == companyId).toList();
    if (rows.length != 1 || (companyId == null && raw.length != 1)) {
      throw StateError('対象の会社を選択して開き直してください。');
    }
    final selectedCompany = rows.single['company_id'];
    if (selectedCompany is! String || selectedCompany.isEmpty) { throw StateError('会社を確認できません。'); }

    // Membership role is authoritative. Once it is loaded, optional home
    // enrichment must never downgrade owner/admin/manager to viewer.
    final role = rows.first['role']?.toString() ?? 'viewer';

    List<dynamic> companies = const [];
    try {
      companies = await _client
          .from('companies')
          .select('name')
          .eq('id', selectedCompany)
          .limit(1).setHeader('Authorization', 'Bearer ${captured.accessToken}');
    } catch (_) {
      // Company display data is optional for role resolution.
    }

    List<dynamic> profiles = const [];
    try {
      profiles = await _client
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .limit(1).setHeader('Authorization', 'Bearer ${captured.accessToken}');
    } catch (_) {
      // Profile display data is optional for role resolution.
    }

    dynamic permissionValue;
    try {
      if (raw.length == 1) {
        permissionValue = await _client.rpc('current_feature_permissions')
            .setHeader('Authorization', 'Bearer ${captured.accessToken}');
      }
    } catch (_) {
      // Feature permission enrichment must not erase the membership role.
    }

    dynamic payrollAdjustmentPermissionValue;
    try {
      if (raw.length == 1) {
        payrollAdjustmentPermissionValue = await _client.rpc('current_payroll_adjustment_permissions')
            .setHeader('Authorization', 'Bearer ${captured.accessToken}');
      }
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

    await lease.ready();
    return HomeIdentity(
      role: role,
      companyId: selectedCompany,
      companyName: companyName,
      displayName: displayName,
      permissions: permissions,
    );
    } finally { lease.dispose(); }
  }
}
