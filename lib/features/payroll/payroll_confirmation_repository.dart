import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
int _integer(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
DateTime? _date(dynamic value) => DateTime.tryParse(value?.toString() ?? '');
String _month(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-01';

class PayrollConfirmationCandidate {
  const PayrollConfirmationCandidate({
    required this.userId,
    required this.name,
    required this.role,
    this.selectedPosition,
  });
  factory PayrollConfirmationCandidate.fromJson(Map<String, dynamic> json) =>
      PayrollConfirmationCandidate(
        userId: json['user_id']?.toString() ?? '',
        name: json['display_name']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        selectedPosition: json['selected_position'] == null
            ? null
            : _integer(json['selected_position']),
      );
  final String userId;
  final String name;
  final String role;
  final int? selectedPosition;
}

class PayrollConfirmationSettings {
  const PayrollConfirmationSettings({
    required this.paymentDay,
    required this.paymentMonthOffset,
    required this.closingDay,
    required this.canManageSettings,
    required this.candidates,
  });
  factory PayrollConfirmationSettings.fromJson(
    Map<String, dynamic> policy,
    List<dynamic> rows,
  ) => PayrollConfirmationSettings(
    paymentDay: _integer(policy['payment_day'], 25),
    paymentMonthOffset: _integer(policy['payment_month_offset'], 1),
    closingDay: _integer(policy['closing_day'], 31),
    canManageSettings: policy['can_manage_settings'] == true,
    candidates: List.unmodifiable(
      rows
          .whereType<Map>()
          .map((row) => PayrollConfirmationCandidate.fromJson(_map(row)))
          .where((row) => row.userId.isNotEmpty),
    ),
  );
  final int paymentDay;
  final int paymentMonthOffset;
  final int closingDay;
  final bool canManageSettings;
  final List<PayrollConfirmationCandidate> candidates;
  List<String> get reviewerUserIds {
    final selected =
        candidates.where((row) => row.selectedPosition != null).toList()
          ..sort((a, b) => a.selectedPosition!.compareTo(b.selectedPosition!));
    return List.unmodifiable(selected.map((row) => row.userId));
  }
}

class PayrollConfirmationReviewer {
  const PayrollConfirmationReviewer({
    required this.userId,
    required this.name,
    required this.position,
    required this.confirmedAt,
  });
  factory PayrollConfirmationReviewer.fromJson(Map<String, dynamic> json) =>
      PayrollConfirmationReviewer(
        userId: json['user_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        position: _integer(json['position']),
        confirmedAt: json['confirmed'] == true
            ? _date(json['confirmed_at'])
            : null,
      );
  final String userId;
  final String name;
  final int position;
  final DateTime? confirmedAt;
  bool get confirmed => confirmedAt != null;
  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'name': name,
    'position': position,
    'confirmed': confirmed,
    'confirmed_at': confirmedAt?.toIso8601String(),
  };
}

class PayrollConfirmationStatus {
  const PayrollConfirmationStatus({
    required this.periodStart,
    required this.confirmationOpenDate,
    required this.payday,
    required this.canConfirm,
    required this.canCancel,
    required this.reviewerConfirmed,
    required this.confirmed,
    required this.reviewers,
  });
  factory PayrollConfirmationStatus.fromJson(Map<String, dynamic> json) =>
      PayrollConfirmationStatus(
        periodStart: _date(json['period_start']),
        confirmationOpenDate: _date(json['confirmation_open_date']),
        payday: _date(json['payday']),
        canConfirm: json['can_confirm'] == true,
        canCancel: json['can_cancel'] == true,
        reviewerConfirmed: json['reviewer_confirmed'] == true,
        confirmed: json['confirmed'] == true,
        reviewers: List.unmodifiable(
          (json['reviewers'] is List ? json['reviewers'] as List : const [])
              .whereType<Map>()
              .map((row) => PayrollConfirmationReviewer.fromJson(_map(row))),
        ),
      );
  final DateTime? periodStart;
  final DateTime? confirmationOpenDate;
  final DateTime? payday;
  final bool canConfirm;
  final bool canCancel;
  final bool reviewerConfirmed;
  final bool confirmed;
  final List<PayrollConfirmationReviewer> reviewers;
  int get requiredCount => reviewers.length;
  int get confirmedCount => reviewers.where((row) => row.confirmed).length;
  Map<String, dynamic> get pdfDetail => {
    'payroll_confirmations': reviewers
        .map((row) => row.toJson())
        .toList(growable: false),
    'required_count': requiredCount,
    if (payday != null)
      'payment_date':
          '${payday!.year.toString().padLeft(4, '0')}-${payday!.month.toString().padLeft(2, '0')}-${payday!.day.toString().padLeft(2, '0')}',
  };
}

class PayrollConfirmationRepository {
  PayrollConfirmationRepository._(this._client);
  final SupabaseClient _client;
  static PayrollConfirmationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PayrollConfirmationRepository._(client);
  }

  Future<PayrollConfirmationSettings> loadSettings() async {
    final policy = await _client.rpc('payroll_company_policy');
    final rows = await _client.rpc('payroll_confirmation_candidates');
    return PayrollConfirmationSettings.fromJson(
      _map(policy),
      rows is List ? rows : const [],
    );
  }

  static void validatePaymentPolicy({
    required int paymentDay,
    required int paymentMonthOffset,
    int closingDay = 31,
  }) {
    if (paymentDay < 1 ||
        paymentDay > 31 ||
        paymentMonthOffset < 0 ||
        paymentMonthOffset > 2 ||
        closingDay != 31) {
      throw ArgumentError('給料日または締め日の設定を確認してください。');
    }
    if (paymentMonthOffset == 0 && paymentDay != 31) {
      throw ArgumentError('末締めの当月払いは月末（31日）を選択してください。');
    }
  }

  Future<void> saveSettings({
    required List<String> reviewerUserIds,
    required int paymentDay,
    required int paymentMonthOffset,
    int closingDay = 31,
  }) async {
    if (reviewerUserIds.isEmpty ||
        reviewerUserIds.length > 3 ||
        reviewerUserIds.toSet().length != reviewerUserIds.length ||
        reviewerUserIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('確認者は重複しない1〜3名を選択してください。');
    }
    validatePaymentPolicy(
      paymentDay: paymentDay,
      paymentMonthOffset: paymentMonthOffset,
      closingDay: closingDay,
    );
    await _client.rpc(
      'set_payroll_confirmation_settings',
      params: {
        'p_user_ids': reviewerUserIds,
        'p_payment_day': paymentDay,
        'p_payment_month_offset': paymentMonthOffset,
        'p_closing_day': closingDay,
      },
    );
  }

  Future<PayrollConfirmationStatus> loadStatus(DateTime month) async =>
      PayrollConfirmationStatus.fromJson(
        _map(
          await _client.rpc(
            'payroll_confirmation_status',
            params: {'p_period_start': _month(month)},
          ),
        ),
      );
  Future<void> setReviewCheck({
    required String statementId,
    required int revision,
    required bool checked,
  }) async {
    await _client.rpc(
      'set_payroll_review_check',
      params: {
        'p_statement_id': statementId,
        'p_revision': revision,
        'p_checked': checked,
      },
    );
  }

  Future<int> confirmMonth(DateTime month) async => _integer(
    await _client.rpc(
      'confirm_payroll_review_month',
      params: {'p_period_start': _month(month)},
    ),
  );
  Future<void> cancelMonth(DateTime month) async {
    await _client.rpc(
      'cancel_payroll_review_month',
      params: {'p_period_start': _month(month)},
    );
  }
}
