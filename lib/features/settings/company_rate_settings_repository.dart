import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CompanyRateSettings {
  const CompanyRateSettings({
    required this.taxRate,
    required this.welfareRate,
    required this.overtimeHourRateYen,
    required this.earlyHourRateYen,
    required this.nightHourRateYen,
    required this.holidayDayRateYen,
    required this.allowance1Name,
    required this.allowance1AmountYen,
    this.allowance1Unit = '回',
    required this.allowance2Name,
    required this.allowance2AmountYen,
    this.allowance2Unit = '回',
    required this.allowance3Name,
    required this.allowance3AmountYen,
    this.allowance3Unit = '回',
  });

  final double taxRate;
  final double welfareRate;
  final int overtimeHourRateYen;
  final int earlyHourRateYen;
  final int nightHourRateYen;
  final int holidayDayRateYen;
  final String allowance1Name;
  final int allowance1AmountYen;
  final String allowance1Unit;
  final String allowance2Name;
  final int allowance2AmountYen;
  final String allowance2Unit;
  final String allowance3Name;
  final int allowance3AmountYen;
  final String allowance3Unit;

  factory CompanyRateSettings.fromMap(Map<String, dynamic> row) {
    double number(Object? value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    int yen(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return CompanyRateSettings(
      taxRate: number(row['tax_rate']),
      welfareRate: number(row['welfare_rate']),
      overtimeHourRateYen: yen(row['overtime_hour_rate_yen']),
      earlyHourRateYen: yen(row['early_hour_rate_yen']),
      nightHourRateYen: yen(row['night_hour_rate_yen']),
      holidayDayRateYen: yen(row['holiday_day_rate_yen']),
      allowance1Name: row['allowance_1_name']?.toString() ?? '',
      allowance1AmountYen: yen(row['allowance_1_amount_yen']),
      allowance1Unit: row['allowance_1_unit']?.toString().trim().isNotEmpty == true
          ? row['allowance_1_unit'].toString().trim()
          : '回',
      allowance2Name: row['allowance_2_name']?.toString() ?? '',
      allowance2AmountYen: yen(row['allowance_2_amount_yen']),
      allowance2Unit: row['allowance_2_unit']?.toString().trim().isNotEmpty == true
          ? row['allowance_2_unit'].toString().trim()
          : '回',
      allowance3Name: row['allowance_3_name']?.toString() ?? '',
      allowance3AmountYen: yen(row['allowance_3_amount_yen']),
      allowance3Unit: row['allowance_3_unit']?.toString().trim().isNotEmpty == true
          ? row['allowance_3_unit'].toString().trim()
          : '回',
    );
  }
}

class CompanyRateSettingsRepository {
  CompanyRateSettingsRepository._(this._client);

  final SupabaseClient _client;

  static CompanyRateSettingsRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return CompanyRateSettingsRepository._(SupabaseBackend.client);
  }

  Future<CompanyRateSettings> load() async {
    final value = await _client.rpc('company_rate_settings_state');
    if (value is! Map) {
      throw StateError('会社単価設定を読み込めませんでした。');
    }
    return CompanyRateSettings.fromMap(
      Map<String, dynamic>.from(value),
    );
  }

  Future<void> save(CompanyRateSettings value) async {
    await _client.rpc(
      'save_company_rate_settings',
      params: {
        'p_tax_rate': value.taxRate,
        'p_welfare_rate': value.welfareRate,
        'p_overtime_hour_rate_yen': value.overtimeHourRateYen,
        'p_early_hour_rate_yen': value.earlyHourRateYen,
        'p_night_hour_rate_yen': value.nightHourRateYen,
        'p_holiday_day_rate_yen': value.holidayDayRateYen,
        'p_allowance_1_name':
            value.allowance1Name.trim().isEmpty ? null : value.allowance1Name.trim(),
        'p_allowance_1_amount_yen': value.allowance1AmountYen,
        'p_allowance_2_name':
            value.allowance2Name.trim().isEmpty ? null : value.allowance2Name.trim(),
        'p_allowance_2_amount_yen': value.allowance2AmountYen,
        'p_allowance_3_name':
            value.allowance3Name.trim().isEmpty ? null : value.allowance3Name.trim(),
        'p_allowance_3_amount_yen': value.allowance3AmountYen,
      },
    );
    await _client.rpc(
      'save_company_allowance_units',
      params: {
        'p_allowance_1_unit': value.allowance1Unit.trim().isEmpty
            ? '回'
            : value.allowance1Unit.trim(),
        'p_allowance_2_unit': value.allowance2Unit.trim().isEmpty
            ? '回'
            : value.allowance2Unit.trim(),
        'p_allowance_3_unit': value.allowance3Unit.trim().isEmpty
            ? '回'
            : value.allowance3Unit.trim(),
      },
    );
  }
}
