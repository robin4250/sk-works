/// A client-side draft validation contract. The server must independently
/// enforce authorization, scope and revision checks when persistence is wired.
class ShiftDraftRequest {
  ShiftDraftRequest({required this.companyId, required this.workerId,
    required this.siteId, required this.workDate, required this.holiday,
    required this.night, required this.startMinute, required this.endMinute,
    required this.checkLate, required this.checkEarly, required this.revision});

  final String companyId, workerId;
  final String? siteId;
  /// A calendar date, not a UTC instant. The server uses company time zone.
  final DateTime workDate;
  final bool holiday, night, checkLate, checkEarly;
  final int startMinute, endMinute;
  /// Zero represents a new draft; a stale revision must be rejected by server.
  final int revision;

  String? validate() {
    if (companyId.trim().isEmpty || workerId.trim().isEmpty || revision < 0) {
      return '対象の会社または従業員を確認してください。';
    }
    if (workDate.hour != 0 || workDate.minute != 0 || workDate.second != 0 ||
        workDate.millisecond != 0 || workDate.microsecond != 0) {
      return '勤務日を確認してください。';
    }
    if (holiday) return null;
    if (siteId == null || siteId!.trim().isEmpty) return '出勤先を選択してください。';
    if (startMinute < 0 || startMinute >= 1440 || endMinute < 0 || endMinute >= 1440) {
      return '出勤・退勤時間を確認してください。';
    }
    if (startMinute == endMinute) return '出勤時間と退勤時間を変えてください。';
    return null;
  }

  bool get endsNextDay => !holiday && endMinute < startMinute;
}
