/// Read-only access to the server-authorized published schedule.
/// Fail closed on incomplete results rather than presenting them as no shifts.
class OwnPublishedShift {
  const OwnPublishedShift({required this.day, required this.revision, required this.holiday,
    required this.night, required this.startMinute, required this.endMinute,
    required this.checkLate, required this.checkEarly, this.siteId});
  final DateTime day;
  final int revision, startMinute, endMinute;
  final bool holiday, night, checkLate, checkEarly;
  final String? siteId;
}

class OwnPublishedShiftGateway {
  const OwnPublishedShiftGateway(this.call);
  final Future<Object?> Function(String, Map<String, Object?>) call;

  Future<List<OwnPublishedShift>> listMonth(String companyId, DateTime month) async {
    if (companyId.trim().isEmpty) throw const FormatException('会社を確認できません。');
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    String date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final result = await call('list_own_published_shifts', {'p_company': companyId,
      'p_from': date(first), 'p_to': date(last)});
    if (result is! List) throw const FormatException('確定シフトを確認できません。');
    final shifts = <OwnPublishedShift>[];
    final days = <String>{};
    for (final row in result) {
      if (row is! Map || row['work_date'] is! String || row['revision'] is! int || row['plan'] is! Map) {
        throw const FormatException('確定シフトを確認できません。');
      }
      final raw = row['work_date'] as String;
      final day = DateTime.tryParse(raw);
      final plan = row['plan'] as Map;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) || day == null || date(day) != raw ||
          day.isBefore(first) || day.isAfter(last) || !days.add(raw) || (row['revision'] as int) < 1 ||
          (plan['site_id'] != null && (plan['site_id'] is! String || (plan['site_id'] as String).trim().isEmpty)) ||
          plan['holiday'] is! bool || plan['night'] is! bool || plan['check_late'] is! bool ||
          plan['check_early'] is! bool || plan['start_minute'] is! int || plan['end_minute'] is! int ||
          (plan['start_minute'] as int) < 0 || (plan['start_minute'] as int) >= 1440 ||
          (plan['end_minute'] as int) < 0 || (plan['end_minute'] as int) >= 1440) {
        throw const FormatException('確定シフトを確認できません。');
      }
      shifts.add(OwnPublishedShift(day: day, revision: row['revision'] as int,
        siteId: plan['site_id'] as String?, holiday: plan['holiday'] as bool,
        night: plan['night'] as bool, startMinute: plan['start_minute'] as int,
        endMinute: plan['end_minute'] as int, checkLate: plan['check_late'] as bool,
        checkEarly: plan['check_early'] as bool));
    }
    shifts.sort((a, b) => a.day.compareTo(b.day));
    return List.unmodifiable(shifts);
  }
}
