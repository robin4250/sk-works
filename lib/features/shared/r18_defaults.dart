/// Only initial drafts receive defaults. Existing saved appendices stay intact.
Map<String, dynamic> r18InitialValues({
  required Map<String, dynamic> payload,
  required Map<String, dynamic> sourceDefaults,
  required bool hasSavedAttachment,
  required String subjectKind,
}) {
  final result = Map<String, dynamic>.from(payload);
  if (hasSavedAttachment) return result;
  bool blank(String key) => result[key] == null ||
      (result[key] is String && (result[key] as String).trim().isEmpty);

  // Explicit draft/template values precede source and generated fallbacks.
  for (final key in ['issue_date', 'order_date', 'work_name']) {
    final value = sourceDefaults[key];
    if (blank(key) && value is String && value.trim().isNotEmpty) {
      result[key] = value;
    }
  }
  final dateKey = subjectKind == 'payment_certificate'
      ? 'issue_date' : subjectKind == 'invoice' ? 'order_date' : null;
  if (dateKey != null && blank(dateKey)) {
    final month = result['month'];
    final match = month is String
        ? RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(month) : null;
    if (match == null || int.parse(match[1]!) < 1) {
      throw const FormatException('対象月を確認してください。');
    }
    final year = int.parse(match[1]!);
    final number = int.parse(match[2]!);
    if (year == 1 && number == 1) {
      throw const FormatException('契約日を確認してください。');
    }
    final previous = DateTime.utc(year, number - 1, 15);
    result[dateKey] = '${previous.year.toString().padLeft(4, '0')}-'
        '${previous.month.toString().padLeft(2, '0')}-15';
  }
  // This value must be supplied by the already-authorized source workspace.
  // Never guess a subject, derive rates from totals, or fetch another company.
  final subject = sourceDefaults['invoice_subject'];
  if (blank('work_name') && subject is String && subject.trim().isNotEmpty) {
    result['work_name'] = subject;
  }
  // Acceptance issue_date is deliberately not inferred as contract date + 1.
  return result;
}
