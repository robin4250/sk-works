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
    this.stampSurname,
    this.draftStampSurname,
    this.canCurrentUserSetStampSurname = false,
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
  final String? stampSurname;
  final String? draftStampSurname;
  final bool canCurrentUserSetStampSurname;

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

class InvoiceStampSurnameReadException implements Exception {
  const InvoiceStampSurnameReadException();
  @override
  String toString() => '承認印の名字を確認できません。再確認してから帳票を開いてください。';
}

class InvoiceStampSurnameMetadata {
  const InvoiceStampSurnameMetadata({this.snapshotSurname, this.draftSurname, this.canSet = false});
  final String? snapshotSurname;
  final String? draftSurname;
  final bool canSet;

  static InvoiceStampSurnameMetadata match(
    String invoiceId,
    Map<String, dynamic> approval,
    Map<String, dynamic>? name,
  ) {
    if (name == null || name['invoice_id'] != invoiceId ||
        name['user_id'] != approval['approver_user_id'] ||
        name['status'] != approval['status']) {
      return const InvoiceStampSurnameMetadata();
    }
    if (approval['status'] == 'approved') {
      final actual = DateTime.tryParse(approval['approved_at']?.toString() ?? '');
      final captured = DateTime.tryParse(name['approved_at']?.toString() ?? '');
      if (actual == null || captured == null || !actual.isAtSameMomentAs(captured)) {
        return const InvoiceStampSurnameMetadata();
      }
      return InvoiceStampSurnameMetadata(snapshotSurname: _surname(name['snapshot_surname']));
    }
    if (approval['status'] == 'pending' && approval['approved_at'] == null &&
        name['approved_at'] == null && name['can_set_surname'] == true) {
      return InvoiceStampSurnameMetadata(draftSurname: _surname(name['draft_surname']), canSet: true);
    }
    return const InvoiceStampSurnameMetadata();
  }

  static String? _surname(dynamic value) {
    if (value is! String || value.trim().isEmpty || value.length > 30 ||
        value.contains(RegExp(r'[\r\n]'))) {
      return null;
    }
    return value;
  }
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
    Map<String, dynamic>? surnameContract;
    try {
      surnameContract = await _loadSurnameContract(invoiceId);
    } catch (_) {
      // An unknown snapshot must never become a different legacy approval seal.
      throw const InvoiceStampSurnameReadException();
    }
    final names = <String, Map<String, dynamic>>{};
    final nameRows = surnameContract?['names'];
    if (nameRows is List) {
      for (final value in nameRows) {
        if (value is Map && value['user_id'] is String) {
          names[value['user_id'] as String] = Map<String, dynamic>.from(value);
        }
      }
    }
    return raw.map((value) {
      final row = Map<String, dynamic>.from(value as Map);
      final surname = InvoiceStampSurnameMetadata.match(invoiceId, row, names[row['approver_user_id']]);
      return InvoiceApprovalRecord(
        userId: row['approver_user_id']?.toString() ?? '',
        name: row['approver_name']?.toString() ?? 'SKOユーザー',
        stampSurname: surname.snapshotSurname,
        draftStampSurname: surname.draftSurname,
        canCurrentUserSetStampSurname: surname.canSet,
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
    final surnameContract = await _loadSurnameContract(invoiceId);
    final raw = await _client.rpc(
      surnameContract?['enabled'] == true
          ? 'approve_invoice_with_stamp_surname'
          : 'approve_invoice',
      params: {'p_invoice_id': invoiceId},
    );
    return raw == true;
  }

  Future<Map<String, dynamic>?> _loadSurnameContract(String invoiceId) async {
    try {
      final raw = await _client.rpc(
        'invoice_stamp_surname_rows',
        params: {'p_invoice_id': invoiceId},
      );
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') return null;
      rethrow;
    }
  }

  Future<void> setStampSurname(String invoiceId, String surname) async {
    final value = surname.trim();
    if (value.isEmpty || value.length > 30 || value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('承認印に表示する名字を1〜30文字で入力してください。');
    }
    await _client.rpc('set_invoice_stamp_surname', params: {
      'p_invoice_id': invoiceId,
      'p_surname': value,
    });
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
