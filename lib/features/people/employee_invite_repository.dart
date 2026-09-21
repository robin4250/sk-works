import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

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

  Future<EmployeeInviteResult> createInvite({
    required String name,
    required String phone,
  }) async {
    final response = await _client.functions.invoke(
      'create-employee-invite',
      body: {
        'name': name.trim(),
        'phone': phone.trim(),
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
