class SourceNotificationTarget {
  const SourceNotificationTarget({required this.companyId, required this.eventKey,
    required this.sourceId, required this.workDate});
  final String companyId;
  final String eventKey;
  final String sourceId;
  final DateTime workDate;
  static bool supports(String? key) => key == 'group_report_saved' || key == 'vehicle_driver_started';
  static SourceNotificationTarget parse(Object? value, {
    required String expectedKey, required String expectedSourceId,
  }) {
    if (value is! Map) {
      throw const FormatException('Notification target unavailable');
    }
    final company = value['company_id']?.toString() ?? '';
    final key = value['event_key']?.toString() ?? '';
    final source = value['source_id']?.toString() ?? '';
    final rawDate = value['work_date']?.toString() ?? '';
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
    final date = DateTime.tryParse(rawDate);
    if (!supports(key) || key != expectedKey || source != expectedSourceId ||
        !uuid.hasMatch(company) || !uuid.hasMatch(source) || date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) ||
        date.toIso8601String().substring(0, 10) != rawDate) {
      throw const FormatException('Notification target mismatch');
    }
    return SourceNotificationTarget(companyId: company, eventKey: key,
      sourceId: source, workDate: date);
  }
  String get databaseDate => workDate.toIso8601String().substring(0, 10);
  void validateRow(Map<String, dynamic> row) {
    final dateKey = eventKey == 'group_report_saved' ? 'report_date' : 'work_date';
    if (row['id'] != sourceId || row['company_id'] != companyId || row[dateKey] != databaseDate ||
        (eventKey == 'vehicle_driver_started' && row['event_type'] != 'clock_in')) {
      throw const FormatException('Saved notification target mismatch');
    }
  }
}

/// Report signature state, independent of notification read state.
String sourceReportStatusLabel(Object? status, {required bool english}) => switch (status) {
  'draft' => english ? 'Draft' : '下書き',
  'signed' => english ? 'Signed' : '署名済み',
  _ => english ? 'Status unavailable' : '状態を確認できません',
};
