import '../attendance/japan_holiday.dart';

/// Company-approved defaults for new input, never evidence of a worked shift.
/// Calendar days use the saved clock-in work date; time boundaries use JST.
class CompanyWorkCategoryPolicy {
  const CompanyWorkCategoryPolicy({required this.nightStartMinute,
    required this.nightEndMinute, required this.holidayWeekdays,
    required this.holidayDates, required this.workingDates,
    required this.includeJapaneseHolidays});
  final int nightStartMinute, nightEndMinute;
  final Set<int> holidayWeekdays;
  final Set<String> holidayDates, workingDates;
  final bool includeJapaneseHolidays;

  // Editing seed only. It is never used until an administrator saves it.
  static const editingSeed = CompanyWorkCategoryPolicy(nightStartMinute: 1320,
    nightEndMinute: 300, holidayWeekdays: {7}, holidayDates: {}, workingDates: {},
    includeJapaneseHolidays: false);

  static String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static bool validDateKey(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.year >= 2000 && parsed.year <= 2199 && dateKey(parsed) == value;
  }

  factory CompanyWorkCategoryPolicy.parse(Object? value) {
    Never invalid() => throw const FormatException('会社の勤務区分設定を確認できません。');
    const keys = {'schema', 'night_start_minute', 'night_end_minute',
      'holiday_weekdays', 'holiday_dates', 'working_dates', 'include_japanese_holidays'};
    if (value is! Map || value.length != keys.length || !value.keys.every(keys.contains) || value['schema'] != 1) invalid();
    final start = value['night_start_minute'], end = value['night_end_minute'];
    if (start is! int || end is! int || start < 0 || start > 1439 || end < 0 || end > 1439 || start == end) invalid();
    final days = value['holiday_weekdays'];
    if (days is! List || days.length > 7 || days.any((v) => v is! int || v < 1 || v > 7) || days.toSet().length != days.length) invalid();
    Set<String> dates(String key) {
      final raw = value[key];
      if (raw is! List || raw.length > 730 || raw.any((v) => v is! String || !validDateKey(v)) || raw.toSet().length != raw.length) invalid();
      return Set.unmodifiable(raw.cast<String>());
    }
    final holidays = dates('holiday_dates'), working = dates('working_dates');
    if (holidays.intersection(working).isNotEmpty || value['include_japanese_holidays'] is! bool) invalid();
    return CompanyWorkCategoryPolicy(nightStartMinute: start, nightEndMinute: end,
      holidayWeekdays: Set.unmodifiable(days.cast<int>()), holidayDates: holidays,
      workingDates: working, includeJapaneseHolidays: value['include_japanese_holidays'] as bool);
  }

  Map<String, Object> toJson() => {'schema': 1, 'night_start_minute': nightStartMinute,
    'night_end_minute': nightEndMinute, 'holiday_weekdays': holidayWeekdays.toList()..sort(),
    'holiday_dates': holidayDates.toList()..sort(), 'working_dates': workingDates.toList()..sort(),
    'include_japanese_holidays': includeJapaneseHolidays};

  String propose({required DateTime clockInAt, required DateTime workDate}) {
    // UTC conversion avoids the device timezone deciding day/night.
    final jst = clockInAt.toUtc().add(const Duration(hours: 9));
    final minute = jst.hour * 60 + jst.minute;
    final night = nightStartMinute < nightEndMinute
      ? minute >= nightStartMinute && minute < nightEndMinute
      : minute >= nightStartMinute || minute < nightEndMinute;
    final key = dateKey(workDate);
    final holiday = !workingDates.contains(key) && (holidayDates.contains(key) ||
      holidayWeekdays.contains(workDate.weekday) ||
      includeJapaneseHolidays && JapanHoliday.name(workDate) != null);
    return holiday ? (night ? 'holiday_night' : 'holiday') : (night ? 'night' : 'day');
  }
}
