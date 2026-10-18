bool isExpenseNoticeUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(value);

Map<String, dynamic> parseExpenseNotificationTarget(
  Map<String, dynamic>? value, {
  required String notificationId,
  required String actionKey,
  required String actionId,
}) {
  final completed = actionKey == 'expense_review_completed';
  if (!isExpenseNoticeUuid(notificationId) ||
      !isExpenseNoticeUuid(actionId) ||
      ![
        'expense_review_request',
        'expense_review_completed',
      ].contains(actionKey)) {
    throw const FormatException('Invalid target');
  }
  if (value == null ||
      value['notification_id'] != notificationId ||
      value['action_key'] != actionKey ||
      value['action_id'] != actionId ||
      !isExpenseNoticeUuid(value['company_id']) ||
      !isExpenseNoticeUuid(value['claim_id']) ||
      value['claim'] is! Map) {
    throw const FormatException('Unavailable target');
  }
  final claim = Map<String, dynamic>.from(value['claim'] as Map);
  if (claim['id'] != value['claim_id'] ||
      claim['company_id'] != value['company_id'] ||
      (!completed && claim['id'] != actionId) ||
      claim['revision'] is! int ||
      (claim['revision'] as int) < 1 ||
      claim['amount_yen'] is! int ||
      (claim['amount_yen'] as int) <= 0 ||
      !['pending', 'approved', 'rejected'].contains(claim['approval']) ||
      (completed && claim['approval'] != 'approved') ||
      (completed && claim['allocation'] == 'unallocated') ||
      ![
        'unallocated',
        'ownCompany',
        'subcontractor',
        'customer',
        'other',
      ].contains(claim['allocation'])) {
    throw const FormatException('Unavailable claim');
  }
  for (final key in ['applicant_name', 'description']) {
    if (claim[key] is! String || (claim[key] as String).trim().isEmpty) {
      throw const FormatException('Unavailable claim text');
    }
  }
  final date = claim['incurred_on'];
  if (date is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
    throw const FormatException('Unavailable date');
  }
  if (['subcontractor', 'customer'].contains(claim['allocation']) &&
      (claim['counterparty_name'] is! String ||
          (claim['counterparty_name'] as String).trim().isEmpty)) {
    throw const FormatException('Unavailable allocation');
  }
  final method = claim['settlement_method'];
  if ((completed && method == null) ||
      (method != null &&
          !['payroll', 'cash', 'paid', 'advance'].contains(method))) {
    throw const FormatException('Unavailable settlement');
  }
  if (method != null) {
    final month = claim['settlement_month'];
    if (month is! String ||
        !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(month) ||
        DateTime.tryParse(month)?.toIso8601String().substring(0, 10) != month) {
      throw const FormatException('Unavailable settlement month');
    }
  }
  return Map<String, dynamic>.unmodifiable(claim);
}
