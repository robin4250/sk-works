import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class ApprovalAssigneeOption {
  const ApprovalAssigneeOption({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;
}

class EmployeeInviteResult {
  const EmployeeInviteResult({
    required this.inviteId,
    required this.name,
    required this.phone,
    required this.temporaryPassword,
    required this.qrPayload,
  });

  final String inviteId;
  final String name;
  final String phone;
  final String temporaryPassword;
  final String qrPayload;
}

class EmployeeInviteRepository {
  EmployeeInviteRepository._(this._client);

  final SupabaseClient _client;

  static EmployeeInviteRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return EmployeeInviteRepository._(SupabaseBackend.client);
  }

  Future<List<ApprovalAssigneeOption>> loadCurrentApprovalAssignees() async {
    final value = await _client.rpc('company_approval_assignee_rows');
    if (value is! List) return const [];

    return [
      for (final raw in value)
        if (raw is Map && raw['is_assignee'] == true)
          ApprovalAssigneeOption(
            userId: raw['user_id']?.toString() ?? '',
            displayName: raw['display_name']?.toString() ?? 'SKOユーザー',
            role: raw['role']?.toString() ?? 'manager',
          ),
    ].where((item) => item.userId.isNotEmpty).toList(growable: false);
  }

  Future<EmployeeInviteResult> createInvite({
    required String name,
    required String phone,
    String requestedRole = 'viewer',
    bool requestedApprovalAssignee = false,
    String? replaceApprovalAssigneeUserId,
  }) async {
    final response = await _client.functions.invoke(
      'create-employee-invite',
      body: {
        'name': name.trim(),
        'phone': phone.trim(),
        'requestedRole': requestedRole,
        'requestedApprovalAssignee': requestedApprovalAssignee,
        'replaceApprovalAssigneeUserId': replaceApprovalAssigneeUserId,
      },
    );

    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw StateError('従業員登録を作成できませんでした。');
    }

    final map = Map<String, dynamic>.from(data);
    final error = map['error']?.toString();
    if (error != null && error.isNotEmpty) throw StateError(error);

    return EmployeeInviteResult(
      inviteId: map['inviteId']?.toString() ?? '',
      name: map['name']?.toString() ?? name.trim(),
      phone: map['phone']?.toString() ?? phone.trim(),
      temporaryPassword: map['temporaryPassword']?.toString() ?? '',
      qrPayload: map['qrPayload']?.toString() ?? '',
    );
  }
}
