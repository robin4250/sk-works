import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import 'people_cloud_repository.dart';

class RetirementQueued implements Exception {
  const RetirementQueued();
}

enum RetirementQueueState { none, pending, completed, renewRequired }

/// Retirement preserves worker, membership, and invitation history.
class EmployeeRetirementRepository {
  EmployeeRetirementRepository(this._client);
  final SupabaseClient _client;

  static EmployeeRetirementRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? EmployeeRetirementRepository(SupabaseBackend.client)
      : null;

  Future<RetirementQueueState> queueState({
    required String companyId,
    required String workerId,
    required void Function() verifyContext,
  }) async {
    final owner = AppAuthMutationGateway.forClient(_client);
    final epoch = await owner.externalFlowAdmission();
    final token = _client.auth.currentSession?.accessToken;
    void check() {
      verifyContext();
      if (epoch == null ||
          token == null ||
          !owner.isExternalFlowCurrent(epoch) ||
          _client.auth.currentSession?.accessToken != token) {
        throw const PersonnelScopeChanged();
      }
    }

    check();
    final result = await _client
        .rpc(
          'retirement_render_state_pilot',
          params: {'p_company': companyId, 'p_worker': workerId},
        )
        .setHeader('Authorization', 'Bearer $token');
    check();
    return switch (result) {
      'none' => RetirementQueueState.none,
      'pending' => RetirementQueueState.pending,
      'completed' => RetirementQueueState.completed,
      'renew_required' => RetirementQueueState.renewRequired,
      _ => throw StateError('退職処理の状態を確認できません。'),
    };
  }

  Future<void> retire({
    required String companyId,
    required String workerId,
    required void Function() verifyContext,
  }) async {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (!uuid.hasMatch(companyId) || !uuid.hasMatch(workerId)) {
      throw StateError('対象を確認してください。');
    }
    final owner = AppAuthMutationGateway.forClient(_client);
    final epoch = await owner.externalFlowAdmission();
    final token = _client.auth.currentSession?.accessToken;
    void check() {
      verifyContext();
      if (epoch == null ||
          token == null ||
          !owner.isExternalFlowCurrent(epoch) ||
          _client.auth.currentSession?.accessToken != token) {
        throw const PersonnelScopeChanged();
      }
    }

    check();
    final people = PeopleCloudRepository.forClient(_client);
    final before = await people.readPersonnel(expectedCompany: companyId);
    check();
    if (!before.canManage ||
        !before.records.any(
          (row) =>
              row['id'] == workerId &&
              row['active'] == true &&
              row['kind'] != 'partnerCompany',
        )) {
      throw StateError('対象または管理権限を確認できません。');
    }
    final job = await _client
        .rpc(
          'request_retirement_render_pilot',
          params: {'p_company': companyId, 'p_worker': workerId},
        )
        .setHeader('Authorization', 'Bearer $token')
        .retry(enabled: false);
    check();
    if (job is! String || !uuid.hasMatch(job)) {
      throw StateError('退職処理の受付を確認できません。');
    }
    throw const RetirementQueued();
  }
}
