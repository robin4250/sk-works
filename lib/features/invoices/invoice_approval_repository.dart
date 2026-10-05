import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class InvoiceApproverCandidate {
  const InvoiceApproverCandidate({
    required this.userId,
    required this.displayName,
    required this.role,
    this.selectedPosition,
  });

  final String userId;
  final String displayName;
  final String role;
  final int? selectedPosition;
}

class InvoiceApprovalRecord {
  const InvoiceApprovalRecord({
    required this.userId,
    required this.name,
    required this.position,
    required this.status,
    required this.canCurrentUserApprove,
    this.approvedAt,
  });

  final String userId;
  final String name;
  final int position;
  final String status;
  final DateTime? approvedAt;
  final bool canCurrentUserApprove;

  bool get approved => status == 'approved';
}

class InvoiceApprovalRepository {
  InvoiceApprovalRepository._(this._client);

  final SupabaseClient _client;

  static InvoiceApprovalRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return InvoiceApprovalRepository._(client);
  }

  Future<List<InvoiceApproverCandidate>> loadCandidates() async {
    final raw = await _client.rpc('invoice_approver_rows');
    if (raw is! List) return const [];
    return raw.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return InvoiceApproverCandidate(
        userId: row['user_id']?.toString() ?? '',
        displayName: row['display_name']?.toString() ?? 'SKOユーザー',
        role: row['role']?.toString() ?? '',
        selectedPosition: (row['selected_position'] as num?)?.toInt(),
      );
    }).toList();
  }

  Future<void> saveApprovers(List<String> userIds) async {
    await _client.rpc('set_invoice_approvers', params: {
      'p_user_ids': userIds,
    });
  }

  Future<List<InvoiceApprovalRecord>> loadForInvoice(String invoiceId) async {
    if (invoiceId.isEmpty) return const [];
    final raw = await _client.rpc(
      'invoice_approval_status_rows',
      params: {'p_invoice_id': invoiceId},
    );
    if (raw is! List) return const [];
    return raw.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return InvoiceApprovalRecord(
        userId: row['approver_user_id']?.toString() ?? '',
        name: row['approver_name']?.toString() ?? 'SKOユーザー',
        position: (row['position'] as num?)?.toInt() ?? 1,
        status: row['status']?.toString() ?? 'pending',
        approvedAt: DateTime.tryParse(row['approved_at']?.toString() ?? ''),
        canCurrentUserApprove: row['can_current_user_approve'] == true,
      );
    }).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<bool> approve(String invoiceId) async {
    final raw = await _client.rpc(
      'approve_invoice',
      params: {'p_invoice_id': invoiceId},
    );
    return raw == true;
  }

  Future<void> enqueueDueNotifications() async {
    await _client.rpc('enqueue_due_invoice_approval_notifications');
  }
}
