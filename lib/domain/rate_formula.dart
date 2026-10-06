enum RateBaseMode { daily, hourly }

class RateFormulaConfig {
  const RateFormulaConfig({
    this.baseMode = RateBaseMode.daily,
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

  final RateBaseMode baseMode;
  final double hoursPerDay;
  final double overtimeMultiplier;
  final double earlyMultiplier;
  final double nightMultiplier;
  final double nightOvertimeMultiplier;
  final double holidayMultiplier;
  final double holidayOvertimeMultiplier;
  final double holidayNightMultiplier;
  final double holidayNightOvertimeMultiplier;

  factory RateFormulaConfig.fromJson(Object? raw) {
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    double number(String key, double fallback) =>
        (map[key] as num?)?.toDouble() ??
        double.tryParse(map[key]?.toString() ?? '') ??
        fallback;
    return RateFormulaConfig(
      baseMode: map['base_mode']?.toString() == 'hourly'
          ? RateBaseMode.hourly
          : RateBaseMode.daily,
      hoursPerDay: number('hours_per_day', 8).clamp(0.01, 24),
      overtimeMultiplier: number('overtime_multiplier', 1.25),
      earlyMultiplier: number('early_multiplier', 1.25),
      nightMultiplier: number('night_multiplier', 1.5),
      nightOvertimeMultiplier:
          number('night_overtime_multiplier', 1.25),
      holidayMultiplier: number('holiday_multiplier', 1.35),
      holidayOvertimeMultiplier:
          number('holiday_overtime_multiplier', 1.25),
      holidayNightMultiplier:
          number('holiday_night_multiplier', 1.6),
      holidayNightOvertimeMultiplier:
          number('holiday_night_overtime_multiplier', 1.25),
    );
  }

  Map<String, Object> toJson() => {
        'base_mode': baseMode == RateBaseMode.hourly ? 'hourly' : 'daily',
        'hours_per_day': hoursPerDay,
        'overtime_multiplier': overtimeMultiplier,
        'early_multiplier': earlyMultiplier,
        'night_multiplier': nightMultiplier,
        'night_overtime_multiplier': nightOvertimeMultiplier,
        'holiday_multiplier': holidayMultiplier,
        'holiday_overtime_multiplier': holidayOvertimeMultiplier,
        'holiday_night_multiplier': holidayNightMultiplier,
        'holiday_night_overtime_multiplier':
            holidayNightOvertimeMultiplier,
      };
}

class CalculatedRates {
  const CalculatedRates({
    required this.daily,
    required this.hourly,
    required this.overtime,
    required this.early,
    required this.nightDay,
    required this.nightOvertime,
    required this.holidayDay,
    required this.holidayOvertime,
    required this.holidayNightDay,
    required this.holidayNightOvertime,
  });

  final int daily;
  final int hourly;
  final int overtime;
  final int early;
  final int nightDay;
  final int nightOvertime;
  final int holidayDay;
  final int holidayOvertime;
  final int holidayNightDay;
  final int holidayNightOvertime;
}

CalculatedRates calculateRates({
  required int baseRateYen,
  required RateFormulaConfig formula,
}) {
  final hours = formula.hoursPerDay <= 0 ? 8 : formula.hoursPerDay;
  final baseHourly = formula.baseMode == RateBaseMode.hourly
      ? baseRateYen.toDouble()
      : baseRateYen / hours;
  final baseDaily = formula.baseMode == RateBaseMode.hourly
      ? baseRateYen * hours
      : baseRateYen.toDouble();

  int round(num value) => value.round();

  final nightDay = round(baseDaily * formula.nightMultiplier);
  final holidayDay = round(baseDaily * formula.holidayMultiplier);
  final holidayNightDay =
      round(baseDaily * formula.holidayNightMultiplier);

  return CalculatedRates(
    daily: round(baseDaily),
    hourly: round(baseHourly),
    overtime: round(baseHourly * formula.overtimeMultiplier),
    early: round(baseHourly * formula.earlyMultiplier),
    nightDay: nightDay,
    nightOvertime: round(
      (nightDay / hours) * formula.nightOvertimeMultiplier,
    ),
    holidayDay: holidayDay,
    holidayOvertime: round(
      (holidayDay / hours) * formula.holidayOvertimeMultiplier,
    ),
    holidayNightDay: holidayNightDay,
    holidayNightOvertime: round(
      (holidayNightDay / hours) *
          formula.holidayNightOvertimeMultiplier,
    ),
  );
}

String rateFormulaLabel({
  required String kind,
  required int baseRateYen,
  required RateFormulaConfig formula,
}) {
  final base = formula.baseMode == RateBaseMode.hourly
      ? '時給'
      : '1日単価';
  final divide = formula.baseMode == RateBaseMode.hourly
      ? ''
      : '÷${_clean(formula.hoursPerDay)}';
  final dailyFromHourly = formula.baseMode == RateBaseMode.hourly
      ? '×${_clean(formula.hoursPerDay)}'
      : '';

  return switch (kind) {
    'overtime' =>
      '$base$divide×${_clean(formula.overtimeMultiplier)}',
    'early' => '$base$divide×${_clean(formula.earlyMultiplier)}',
    'night' =>
      '$base$dailyFromHourly×${_clean(formula.nightMultiplier)}',
    'night_overtime' =>
      '$base$divide×${_clean(formula.nightMultiplier)}×${_clean(formula.nightOvertimeMultiplier)}',
    'holiday' =>
      '$base$dailyFromHourly×${_clean(formula.holidayMultiplier)}',
    'holiday_overtime' =>
      '$base$divide×${_clean(formula.holidayMultiplier)}×${_clean(formula.holidayOvertimeMultiplier)}',
    'holiday_night' =>
      '$base$dailyFromHourly×${_clean(formula.holidayNightMultiplier)}',
    'holiday_night_overtime' =>
      '$base$divide×${_clean(formula.holidayNightMultiplier)}×${_clean(formula.holidayNightOvertimeMultiplier)}',
    _ => '$base=$baseRateYen',
  };
}

String _clean(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
