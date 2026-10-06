class RateFormulaSettings {
  const RateFormulaSettings({
    this.hoursPerDay = 8,
    this.hourlyBase = false,
    this.overtimeMultiplier = 1.25,
    this.earlyMultiplier = 1.25,
    this.nightMultiplier = 1.5,
    this.nightOvertimeMultiplier = 1.25,
    this.holidayMultiplier = 1.35,
    this.holidayOvertimeMultiplier = 1.25,
    this.holidayNightMultiplier = 1.6,
    this.holidayNightOvertimeMultiplier = 1.25,
  });

  final double hoursPerDay;
  final bool hourlyBase;
  final double overtimeMultiplier;
  final double earlyMultiplier;
  final double nightMultiplier;
  final double nightOvertimeMultiplier;
  final double holidayMultiplier;
  final double holidayOvertimeMultiplier;
  final double holidayNightMultiplier;
  final double holidayNightOvertimeMultiplier;

  factory RateFormulaSettings.fromMap(Object? raw) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    double v(String key, double fallback) {
      final value = map[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final hourly = map['hourly_base'];
    final baseMode = map['base_mode']?.toString();
    return RateFormulaSettings(
      hoursPerDay: v('hours_per_day', 8),
      hourlyBase: baseMode == 'hourly' ||
          hourly == true || hourly?.toString() == 'true',
      overtimeMultiplier: v('overtime_multiplier', 1.25),
      earlyMultiplier: v('early_multiplier', 1.25),
      nightMultiplier: v('night_multiplier', 1.5),
      nightOvertimeMultiplier: v('night_overtime_multiplier', 1.25),
      holidayMultiplier: v('holiday_multiplier', 1.35),
      holidayOvertimeMultiplier: v('holiday_overtime_multiplier', 1.25),
      holidayNightMultiplier: v('holiday_night_multiplier', 1.6),
      holidayNightOvertimeMultiplier:
          v('holiday_night_overtime_multiplier', 1.25),
    );
  }

  Map<String, dynamic> toMap({int? hourlyRateYen}) => {
        'hours_per_day': hoursPerDay,
        'hourly_base': hourlyBase,
        'base_mode': hourlyBase ? 'hourly' : 'daily',
        'hourly_rate_yen': hourlyBase ? (hourlyRateYen ?? 0) : 0,
        'overtime_multiplier': overtimeMultiplier,
        'early_multiplier': earlyMultiplier,
        'night_multiplier': nightMultiplier,
        'night_overtime_multiplier': nightOvertimeMultiplier,
        'holiday_multiplier': holidayMultiplier,
        'holiday_overtime_multiplier': holidayOvertimeMultiplier,
        'holiday_night_multiplier': holidayNightMultiplier,
        'holiday_night_overtime_multiplier': holidayNightOvertimeMultiplier,
      };

  int dailyBase(int baseRate, {bool? hourlyBase}) => _round(
        _dailyBase(baseRate, hourlyBase ?? this.hourlyBase),
      );

  int overtime(int baseRate, {bool? hourlyBase}) => _round(
        _hourlyBase(baseRate, hourlyBase ?? this.hourlyBase) * overtimeMultiplier,
      );
  int early(int baseRate, {bool? hourlyBase}) => _round(
        _hourlyBase(baseRate, hourlyBase ?? this.hourlyBase) * earlyMultiplier,
      );
  int night(int baseRate, {bool? hourlyBase}) => _round(
        _dailyBase(baseRate, hourlyBase ?? this.hourlyBase) * nightMultiplier,
      );
  int nightOvertime(int baseRate, {bool? hourlyBase}) => _round(
        _hourlyBase(baseRate, hourlyBase ?? this.hourlyBase) *
            nightMultiplier *
            nightOvertimeMultiplier,
      );
  int holiday(int baseRate, {bool? hourlyBase}) => _round(
        _dailyBase(baseRate, hourlyBase ?? this.hourlyBase) *
            holidayMultiplier,
      );
  int holidayOvertime(int baseRate, {bool? hourlyBase}) => _round(
        _hourlyBase(baseRate, hourlyBase ?? this.hourlyBase) *
            holidayMultiplier *
            holidayOvertimeMultiplier,
      );
  int holidayNight(int baseRate, {bool? hourlyBase}) => _round(
        _dailyBase(baseRate, hourlyBase ?? this.hourlyBase) *
            holidayNightMultiplier,
      );
  int holidayNightOvertime(int baseRate, {bool? hourlyBase}) => _round(
        _hourlyBase(
              holidayNight(baseRate, hourlyBase: hourlyBase ?? this.hourlyBase),
              hourlyBase ?? this.hourlyBase,
            ) *
            holidayNightOvertimeMultiplier,
      );

  double get _hours => hoursPerDay <= 0 ? 8 : hoursPerDay;
  double _hourlyBase(int baseRate, bool hourly) =>
      hourly ? baseRate.toDouble() : baseRate / _hours;
  double _dailyBase(int baseRate, bool hourly) =>
      hourly ? baseRate * _hours : baseRate.toDouble();
  int _round(double value) => value.round();

  String overtimeFormula(int baseRate, {bool? hourlyBase}) => (hourlyBase ?? this.hourlyBase)
      ? '$baseRate × ${_fmt(overtimeMultiplier)}'
      : '$baseRate ÷ ${_fmt(_hours)} × ${_fmt(overtimeMultiplier)}';
  String earlyFormula(int baseRate, {bool? hourlyBase}) => (hourlyBase ?? this.hourlyBase)
      ? '$baseRate × ${_fmt(earlyMultiplier)}'
      : '$baseRate ÷ ${_fmt(_hours)} × ${_fmt(earlyMultiplier)}';
  String nightFormula(int baseRate, {bool? hourlyBase}) =>
      (hourlyBase ?? this.hourlyBase)
          ? '$baseRate × ${_fmt(_hours)} × ${_fmt(nightMultiplier)}'
          : '$baseRate × ${_fmt(nightMultiplier)}';
  String nightOvertimeFormula(int baseRate, {bool? hourlyBase}) {
    return (hourlyBase ?? this.hourlyBase)
        ? '$baseRate × ${_fmt(nightMultiplier)} × ${_fmt(nightOvertimeMultiplier)}'
        : '$baseRate ÷ ${_fmt(_hours)} × ${_fmt(nightMultiplier)} × ${_fmt(nightOvertimeMultiplier)}';
  }
  String holidayFormula(int baseRate, {bool? hourlyBase}) =>
      (hourlyBase ?? this.hourlyBase)
          ? '$baseRate × ${_fmt(_hours)} × ${_fmt(holidayMultiplier)}'
          : '$baseRate × ${_fmt(holidayMultiplier)}';
  String holidayOvertimeFormula(int baseRate, {bool? hourlyBase}) {
    return (hourlyBase ?? this.hourlyBase)
        ? '$baseRate × ${_fmt(holidayMultiplier)} × ${_fmt(holidayOvertimeMultiplier)}'
        : '$baseRate ÷ ${_fmt(_hours)} × ${_fmt(holidayMultiplier)} × ${_fmt(holidayOvertimeMultiplier)}';
  }
  String holidayNightFormula(int baseRate, {bool? hourlyBase}) =>
      (hourlyBase ?? this.hourlyBase)
          ? '$baseRate × ${_fmt(_hours)} × ${_fmt(holidayNightMultiplier)}'
          : '$baseRate × ${_fmt(holidayNightMultiplier)}';
  String holidayNightOvertimeFormula(
    int baseRate, {
    bool? hourlyBase,
  }) {
    return (hourlyBase ?? this.hourlyBase)
        ? '$baseRate × ${_fmt(holidayNightMultiplier)} × ${_fmt(holidayNightOvertimeMultiplier)}'
        : '$baseRate ÷ ${_fmt(_hours)} × ${_fmt(holidayNightMultiplier)} × ${_fmt(holidayNightOvertimeMultiplier)}';
  }

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

int effectiveRate(int direct, int calculated) => direct > 0 ? direct : calculated;
