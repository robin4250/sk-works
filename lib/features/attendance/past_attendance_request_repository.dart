import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PastAttendanceRequestRepository {
  PastAttendanceRequestRepository._(this._client);

  final SupabaseClient _client;

  static PastAttendanceRequestRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PastAttendanceRequestRepository._(client);
  }

  Future<String> submit({
    required List<Map<String, dynamic>> items,
    required String signerName,
    required Object signatureJson,
  }) async {
    final value = await _client.rpc(
      'submit_past_attendance_request',
      params: {
        'p_items': items,
        'p_signer_name': signerName.trim(),
        'p_signature_json': signatureJson,
      },
    );
    final requestId = value?.toString() ?? '';
    if (requestId.isEmpty) {
      throw StateError('過去のまとめて出勤申請を作成できませんでした。');
    }
    return requestId;
  }
}
