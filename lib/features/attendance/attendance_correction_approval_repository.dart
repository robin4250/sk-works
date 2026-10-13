import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AttendanceCorrectionApprovalRequest {
  const AttendanceCorrectionApprovalRequest({
    required this.id,
    required this.requestedBy,
    required this.requestedByName,
    required this.itemCount,
    required this.signerName,
    required this.submittedAt,
  });

  final String id;
  final String requestedBy;
  final String requestedByName;
  final int itemCount;
  final String signerName;
  final DateTime? submittedAt;
}

class AttendanceCorrectionApprovalItem {
  const AttendanceCorrectionApprovalItem({
    required this.id,
    required this.attendanceEntryId,
    required this.originalSnapshot,
    required this.proposedSnapshot,
    required this.changeSummary,
  });

  final String id;
  final String attendanceEntryId;
  final Map<String, dynamic> originalSnapshot;
  final Map<String, dynamic> proposedSnapshot;
  final String changeSummary;
}

class AttendanceCorrectionApprovalRepository {
  AttendanceCorrectionApprovalRepository._(this._client);

  final SupabaseClient _client;

  static AttendanceCorrectionApprovalRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceCorrectionApprovalRepository._(client);
  }

  Future<List<AttendanceCorrectionApprovalRequest>> loadPending() async {
    final rows = await _client.rpc('pending_attendance_correction_rows');
    return [
      for (final raw in (rows as List<dynamic>))
        AttendanceCorrectionApprovalRequest(
          id: (raw as Map)['request_id']?.toString() ?? '',
          requestedBy: raw['requested_by']?.toString() ?? '',
          requestedByName:
              raw['requested_by_name']?.toString() ?? 'SKOユーザー',
          itemCount: (raw['item_count'] as num?)?.toInt() ?? 0,
          signerName: raw['signer_name']?.toString() ?? '',
          submittedAt:
              DateTime.tryParse(raw['submitted_at']?.toString() ?? ''),
        ),
    ].where((item) => item.id.isNotEmpty).toList();
  }

  Future<List<AttendanceCorrectionApprovalItem>> loadItems(
    String requestId,
  ) async {
    final rows = await _client.rpc(
      'attendance_correction_item_rows',
      params: {'p_request_id': requestId},
    );

    return [
      for (final raw in (rows as List<dynamic>))
        AttendanceCorrectionApprovalItem(
          id: (raw as Map)['item_id']?.toString() ?? '',
          attendanceEntryId: raw['attendance_entry_id']?.toString() ?? '',
          originalSnapshot: raw['original_snapshot'] is Map
              ? Map<String, dynamic>.from(raw['original_snapshot'] as Map)
              : const {},
          proposedSnapshot: raw['proposed_snapshot'] is Map
              ? Map<String, dynamic>.from(raw['proposed_snapshot'] as Map)
              : const {},
          changeSummary: raw['change_summary']?.toString() ?? '',
        ),
    ].where((item) => item.id.isNotEmpty).toList();
  }

  Future<String> decide({
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    final value = await _client.rpc(
      'decide_attendance_correction_request',
      params: {
        'p_request_id': requestId,
        'p_decision': approve ? 'approve' : 'reject',
        'p_note': note?.trim(),
      },
    );
    return value?.toString() ?? '';
  }
}
