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
    this.smsSent = false,
    this.testFlightUrl,
    this.deliveryMessage,
  });

  final String inviteId;
  final String name;
  final String phone;
  final String temporaryPassword;
  final String qrPayload;
  final bool smsSent;
  final String? testFlightUrl;
  final String? deliveryMessage;
}

class InitialRegistrationEmployee {
  const InitialRegistrationEmployee({
    required this.id,
    required this.name,
    required this.phone,
    required this.invited,
  });

  final String id;
  final String name;
  final String phone;
  final bool invited;
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

  Future<String> registerEmployee({
    required String name,
    required String phone,
  }) async {
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    if (trimmedName.isEmpty || trimmedPhone.isEmpty) {
      throw StateError('名前と電話番号を入力してください。');
    }

    try {
      final value = await _client.rpc(
        'register_employee_preregistration',
        params: {
          'p_name': trimmedName,
          'p_phone': trimmedPhone,
        },
      );
      if (value is! String || value.isEmpty) {
        throw StateError('登録結果を確認できません。重複登録せず一覧を確認してください。');
      }
      return value;
    } on PostgrestException catch (error) {
      if (error.message.contains('employee phone already registered')) {
        throw StateError('この電話番号の従業員はすでに登録されています。');
      }
      rethrow;
    }
  }

  Future<String> loadTestFlightUrl() async {
    final raw = await _client.rpc('initial_registration_distribution_settings');
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return map['testflight_url']?.toString() ?? '';
  }

  Future<void> saveTestFlightUrl(String value) async {
    await _client.rpc(
      'save_initial_registration_distribution_settings',
      params: {'p_testflight_url': value.trim()},
    );
  }

  Future<List<InitialRegistrationEmployee>> loadRegisteredEmployees() async {
    final value = await _client.rpc('initial_registration_employee_rows');
    final rows = value is List ? value : const <dynamic>[];

    return [
      for (final raw in rows)
        if ((raw['phone']?.toString().trim() ?? '').isNotEmpty)
          InitialRegistrationEmployee(
            id: raw['id']?.toString() ?? '',
            name: raw['name']?.toString() ?? '名前未登録',
            phone: raw['phone']?.toString() ?? '',
            invited: (raw['user_id']?.toString().trim() ?? '').isNotEmpty,
          ),
    ].where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  Future<EmployeeInviteResult> createInviteForWorker(
    String workerId, {
    bool deliverSms = true,
  }) async {
    final response = await _client.functions.invoke(
      'create-employee-invite',
      body: {
        'workerId': workerId,
        'deliverSms': deliverSms,
      },
    );
    return _resultFromResponse(response);
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
    return _resultFromResponse(
      response,
      fallbackName: name.trim(),
      fallbackPhone: phone.trim(),
    );
  }

  EmployeeInviteResult _resultFromResponse(
    FunctionResponse response, {
    String fallbackName = '',
    String fallbackPhone = '',
  }) {
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw StateError('初回登録を作成できませんでした。');
    }

    final map = Map<String, dynamic>.from(data);
    final error = map['error']?.toString();
    if (error != null && error.isNotEmpty) throw StateError(error);

    return EmployeeInviteResult(
      inviteId: map['inviteId']?.toString() ?? '',
      name: map['name']?.toString() ?? fallbackName,
      phone: map['phone']?.toString() ?? fallbackPhone,
      temporaryPassword: map['temporaryPassword']?.toString() ?? '',
      qrPayload: map['qrPayload']?.toString() ?? '',
      smsSent: map['smsSent'] == true,
      testFlightUrl: map['testFlightUrl']?.toString(),
      deliveryMessage: map['deliveryMessage']?.toString(),
    );
  }
}
