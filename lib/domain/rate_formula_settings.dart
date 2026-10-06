class RateFormulaSettings {
  const RateFormulaSettings({
    this.hoursPerDay = 8,
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

    return RateFormulaSettings(
      hoursPerDay: v('hours_per_day', 8),
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

  Map<String, dynamic> toMap() => {
        'hours_per_day': hoursPerDay,
        'overtime_multiplier': overtimeMultiplier,
        'early_multiplier': earlyMultiplier,
        'night_multiplier': nightMultiplier,
        'night_overtime_multiplier': nightOvertimeMultiplier,
        'holiday_multiplier': holidayMultiplier,
        'holiday_overtime_multiplier': holidayOvertimeMultiplier,
        'holiday_night_multiplier': holidayNightMultiplier,
        'holiday_night_overtime_multiplier': holidayNightOvertimeMultiplier,
      };

  int overtime(int daily) => _round(daily / _hours * overtimeMultiplier);
  int early(int daily) => _round(daily / _hours * earlyMultiplier);
  int night(int daily) => _round(daily * nightMultiplier);
  int nightOvertime(int daily) =>
      _round(night(daily) / _hours * nightOvertimeMultiplier);
  int holiday(int daily) => _round(daily * holidayMultiplier);
  int holidayOvertime(int daily) =>
      _round(holiday(daily) / _hours * holidayOvertimeMultiplier);
  int holidayNight(int daily) => _round(daily * holidayNightMultiplier);
  int holidayNightOvertime(int daily) =>
      _round(holidayNight(daily) / _hours * holidayNightOvertimeMultiplier);

  double get _hours => hoursPerDay <= 0 ? 8 : hoursPerDay;
  int _round(double value) => value.round();

  String overtimeFormula(int daily) =>
      '$daily ÷ ${_fmt(_hours)} × ${_fmt(overtimeMultiplier)}';
  String earlyFormula(int daily) =>
      '$daily ÷ ${_fmt(_hours)} × ${_fmt(earlyMultiplier)}';
  String nightFormula(int daily) =>
      '$daily × ${_fmt(nightMultiplier)}';
  String nightOvertimeFormula(int daily) =>
      '${night(daily)} ÷ ${_fmt(_hours)} × ${_fmt(nightOvertimeMultiplier)}';
  String holidayFormula(int daily) =>
      '$daily × ${_fmt(holidayMultiplier)}';
  String holidayOvertimeFormula(int daily) =>
      '${holiday(daily)} ÷ ${_fmt(_hours)} × ${_fmt(holidayOvertimeMultiplier)}';
  String holidayNightFormula(int daily) =>
      '$daily × ${_fmt(holidayNightMultiplier)}';
  String holidayNightOvertimeFormula(int daily) =>
      '${holidayNight(daily)} ÷ ${_fmt(_hours)} × ${_fmt(holidayNightOvertimeMultiplier)}';

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

int effectiveRate(int direct, int calculated) => direct > 0 ? direct : calculated;
