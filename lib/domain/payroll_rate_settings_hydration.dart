import 'rate_formula_settings.dart';

/// Existing persisted rates remain authoritative when a pre-editor record has
/// no overrides or the schema-default empty map. Positive differences become
/// manual editor overrides; explicit nonempty override maps retain their meaning.
Map<String, dynamic> hydratePayrollRateSettings(Map<String, dynamic> stored) {
  final result = Map<String, dynamic>.from(stored);
  final raw = stored['rate_formula'];
  final formulaMap = raw is Map
      ? Map<String, dynamic>.from(raw)
      : <String, dynamic>{};
  final formula = RateFormulaSettings.fromMap(formulaMap);
  final hourly = stored['pay_type'] != 'monthly' &&
      (stored['pay_type'] == 'hourly' || formula.hourlyBase);
  int amount(Object? value) => value is num
      ? value.round()
      : num.tryParse(value?.toString() ?? '')?.round() ?? 0;
  final hours = formula.hoursPerDay > 0 ? formula.hoursPerDay : 8;
  final hourlyRate = amount(formulaMap['hourly_rate_yen']) > 0
      ? amount(formulaMap['hourly_rate_yen'])
      : amount(stored['hourly_rate_yen']) > 0
          ? amount(stored['hourly_rate_yen'])
          : (amount(stored['day_daily']) / hours).round();
  final base = hourly ? hourlyRate : stored['pay_type'] == 'monthly'
      ? amount(stored['calculation_daily_base_yen'])
      : amount(stored['day_daily']);
  if (hourly) {
    formulaMap['base_mode'] = 'hourly';
    formulaMap['hourly_base'] = true;
    formulaMap['hourly_rate_yen'] = hourlyRate;
    result['rate_formula'] = formulaMap;
  }
  final overrides = stored['rate_overrides'];
  if (overrides is Map && overrides.isNotEmpty) return result;
  final expected = <String, (String, int)>{
    'overtime': ('day_overtime', formula.overtime(base, hourlyBase: hourly)),
    'early': ('day_early', formula.early(base, hourlyBase: hourly)),
    'night': ('night_daily', formula.night(base, hourlyBase: hourly)),
    'night_overtime': ('night_overtime', formula.nightOvertime(base, hourlyBase: hourly)),
    'holiday': ('holiday_daily', formula.holiday(base, hourlyBase: hourly)),
    'holiday_overtime': ('holiday_overtime', formula.holidayOvertime(base, hourlyBase: hourly)),
    'holiday_night': ('holiday_night_daily', formula.holidayNight(base, hourlyBase: hourly)),
    'holiday_night_overtime': ('holiday_night_overtime', formula.holidayNightOvertime(base, hourlyBase: hourly)),
  };
  result['rate_overrides'] = {
    for (final item in expected.entries)
      if (stored.containsKey(item.value.$1) && amount(stored[item.value.$1]) > 0 &&
          amount(stored[item.value.$1]) != item.value.$2)
        item.key: amount(stored[item.value.$1]),
  };
  return result;
}

/// An unrelated allowance/deduction save must not rewrite legacy registered
/// rates, including zero and early-work categories absent from the editor.
void preserveUnchangedPayrollRates(
  Map<String, dynamic> saveValues,
  Map<String, dynamic> stored, {
  required bool unchanged,
}) {
  if (!unchanged) return;
  for (final key in const [
    'day_daily', 'day_overtime', 'day_early',
    'night_daily', 'night_overtime', 'night_early',
    'holiday_daily', 'holiday_overtime', 'holiday_early',
    'holiday_night_daily', 'holiday_night_overtime', 'holiday_night_early',
  ]) {
    if (stored.containsKey(key)) saveValues[key] = stored[key];
  }
}
