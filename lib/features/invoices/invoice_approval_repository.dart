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
    this.displayDate,
    this.displayDateOverride,
    this.displayDateMode = 'actual',
    this.stampRole = 'confirmation',
    this.canCurrentUserCancel = false,
    this.canCurrentUserEditDisplayDate = false,
  });

  final String userId;
  final String name;
  final int position;
  final String status;
  final DateTime? approvedAt;
  final bool canCurrentUserApprove;
  final DateTime? displayDate;
  final DateTime? displayDateOverride;
  final String displayDateMode;
  final String stampRole;
  final bool canCurrentUserCancel;
  final bool canCurrentUserEditDisplayDate;

  // Display dates never modify or substitute the actual approval timestamp.
  DateTime? get stampDisplayDate {
    if (!approved) return null;
    if (displayDateOverride != null) return displayDateOverride;
    if (displayDateMode == 'none') return null;
    if (displayDate != null) return displayDate;
    return displayDateMode == 'actual'
        ? InvoiceApprovalRepository._japanDate(approvedAt)
        : null;
  }

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
    await _client.rpc('set_invoice_approvers', params: {'p_user_ids': userIds});
  }

  Future<List<InvoiceApprovalRecord>> loadForInvoice(String invoiceId) async {
    if (invoiceId.isEmpty) return const [];
    dynamic raw;
    var legacy = false;
    try {
      raw = await _client.rpc(
        'invoice_approval_status_rows_v2',
        params: {'p_invoice_id': invoiceId},
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      legacy = true;
      raw = await _client.rpc(
        'invoice_approval_status_rows',
        params: {'p_invoice_id': invoiceId},
      );
    }
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
        displayDate: legacy
            ? _japanDate(row['approved_at'])
            : DateTime.tryParse(row['display_date']?.toString() ?? ''),
        displayDateOverride: DateTime.tryParse(
          row['display_date_override']?.toString() ?? '',
        ),
        displayDateMode: row['display_date_mode']?.toString() ?? 'actual',
        stampRole: row['stamp_role']?.toString() ?? 'confirmation',
        canCurrentUserCancel: row['can_current_user_cancel'] == true,
        canCurrentUserEditDisplayDate:
            row['can_current_user_edit_display_date'] == true,
      );
    }).toList()..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<bool> approve(String invoiceId) async {
    final raw = await _client.rpc(
      'approve_invoice',
      params: {'p_invoice_id': invoiceId},
    );
    return raw == true;
  }

  static DateTime? _japanDate(dynamic value) {
    final timestamp = DateTime.tryParse(value?.toString() ?? '');
    if (timestamp == null) return null;
    final japan = timestamp.toUtc().add(const Duration(hours: 9));
    return DateTime(japan.year, japan.month, japan.day);
  }

  Future<void> cancel(String invoiceId) async {
    await _client.rpc(
      'cancel_invoice_approval',
      params: {'p_invoice_id': invoiceId},
    );
  }

  Future<void> setDisplayDate(
    String invoiceId,
    String approverUserId,
    DateTime? date,
  ) async {
    await _client.rpc(
      'set_invoice_stamp_display_date',
      params: {
        'p_invoice_id': invoiceId,
        'p_approver_user_id': approverUserId,
        'p_display_date': date == null
            ? null
            : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      },
    );
  }

  Future<String?> loadDatePolicy() async {
    try {
      final raw = await _client.rpc('invoice_stamp_date_policy');
      return raw is Map ? raw['mode']?.toString() : null;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') return null;
      rethrow;
    }
  }

  Future<void> saveDatePolicy(String mode) async {
    if (!const ['actual', 'closing', 'none'].contains(mode)) {
      throw ArgumentError.value(mode, 'mode');
    }
    await _client.rpc(
      'set_invoice_stamp_date_policy',
      params: {'p_mode': mode},
    );
  }

  Future<List<InvoiceApprovalHistoryRecord>> loadHistory(
    String invoiceId,
  ) async {
    final raw = await _client.rpc(
      'invoice_approval_history',
      params: {'p_invoice_id': invoiceId},
    );
    if (raw is! List) return const [];
    return raw.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      return InvoiceApprovalHistoryRecord(
        actorName: row['actor_name']?.toString() ?? 'SKOユーザー',
        action: row['action']?.toString() ?? '',
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      );
    }).toList();
  }

  Future<void> enqueueDueNotifications() async {
    await _client.rpc('enqueue_due_invoice_approval_notifications');
  }
}

class InvoiceApprovalHistoryRecord {
  const InvoiceApprovalHistoryRecord({
    required this.actorName,
    required this.action,
    required this.createdAt,
  });
  final String actorName;
  final String action;
  final DateTime? createdAt;
}
