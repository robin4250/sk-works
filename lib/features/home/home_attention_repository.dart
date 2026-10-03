import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class RequiredDocumentAttention {
  const RequiredDocumentAttention({
    required this.missingCount,
    required this.missingNames,
    required this.needsLicense,
    required this.needsQualification,
    this.paidLeaveApprovalCount = 0,
  });

  final int missingCount;
  final List<String> missingNames;
  final bool needsLicense;
  final bool needsQualification;
  final int paidLeaveApprovalCount;

  int get unresolvedCount => missingCount + paidLeaveApprovalCount;
  bool get hasMissing => unresolvedCount > 0;
}

class HomeAttentionRepository {
  HomeAttentionRepository._(this._client);

  final SupabaseClient _client;

  static HomeAttentionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return HomeAttentionRepository._(SupabaseBackend.client);
  }

  Future<RequiredDocumentAttention> loadRequiredDocumentAttention() async {
    final value = await _client.rpc('current_user_required_document_attention');
    var paidLeaveApprovalCount = 0;
    try {
      final pending = await _client.rpc('pending_paid_leave_request_batches');
      if (pending is List) paidLeaveApprovalCount = pending.length;
    } catch (_) {
      // Non-management users do not have access to approval queues.
    }
    if (value is! Map) {
      return RequiredDocumentAttention(
        missingCount: 0,
        missingNames: [],
        needsLicense: false,
        needsQualification: false,
        paidLeaveApprovalCount: paidLeaveApprovalCount,
      );
    }
    final row = Map<String, dynamic>.from(value);
    final names = <String>[
      for (final item in (row['missing_names'] as List<dynamic>? ?? const []))
        item.toString(),
    ];
    return RequiredDocumentAttention(
      missingCount: row['missing_count'] is int
          ? row['missing_count'] as int
          : int.tryParse(row['missing_count']?.toString() ?? '') ?? 0,
      missingNames: names,
      needsLicense: row['needs_license'] == true,
      needsQualification: row['needs_qualification'] == true,
      paidLeaveApprovalCount: paidLeaveApprovalCount,
    );
  }
}
