import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import 'people_cloud_repository.dart';

/// Soft retirement only. RLS remains authoritative; no delete or fallback write.
class EmployeeRetirementRepository {
  EmployeeRetirementRepository(this._client);
  final SupabaseClient _client;

  static EmployeeRetirementRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
          ? EmployeeRetirementRepository(SupabaseBackend.client) : null;

  Future<void> retire({required String companyId, required String workerId, required void Function() verifyContext}) async {
    final uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
    if (!uuid.hasMatch(companyId) || !uuid.hasMatch(workerId)) {
      throw StateError('対象を確認してください。');
    }
    final owner = AppAuthMutationGateway.forClient(_client);
    final epoch = await owner.externalFlowAdmission();
    final token = _client.auth.currentSession?.accessToken;
    void check() {
      verifyContext();
      if (epoch == null || token == null || !owner.isExternalFlowCurrent(epoch) ||
          _client.auth.currentSession?.accessToken != token) {
        throw const PersonnelScopeChanged();
      }
    }
    check();
    final people = PeopleCloudRepository.forClient(_client);
    final before = await people.readPersonnel(expectedCompany: companyId);
    check();
    if (!before.canManage || !before.records.any((row) =>
        row['id'] == workerId && row['active'] == true && row['kind'] != 'partnerCompany')) {
      throw StateError('対象または管理権限を確認できません。');
    }
    final rows = await _client.from('workers').update({'status': 'inactive'})
      .eq('id', workerId).eq('company_id', companyId).eq('status', 'active')
      .select('id,company_id,status').setHeader('Authorization', 'Bearer $token');
    check();
    if (rows.length != 1 || rows.single['id'] != workerId ||
        rows.single['company_id'] != companyId || rows.single['status'] != 'inactive') {
      throw StateError('退職結果を確認できません。一覧を再読み込みしてください。');
    }
    final member = await people.membership(companyId: companyId);
    check();
    if (member.companyId != before.company || member.role != before.role) {
      throw const PersonnelScopeChanged();
    }
    final saved = await _client.from('workers').select('id,company_id,status')
      .eq('company_id', companyId).eq('id', workerId)
      .setHeader('Authorization', 'Bearer $token');
    check();
    if (saved.length != 1 || saved.single['status'] != 'inactive') {
      throw StateError('保存後の状態を確認できません。一覧を再読み込みしてください。');
    }
  }
}
