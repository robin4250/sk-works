import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../data/supabase_backend.dart';

class CompanyRateSettings {
  const CompanyRateSettings({
    this.companyId,
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

  final String? companyId;
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
      companyId: row['company_id'] is String ? row['company_id'] as String : null,
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

  Map<String, dynamic> get defaultsValues => {
    'tax_rate': taxRate,
    'welfare_rate': welfareRate,
    'overtime_hour_rate_yen': overtimeHourRateYen,
    'early_hour_rate_yen': earlyHourRateYen,
    'night_hour_rate_yen': nightHourRateYen,
    'holiday_day_rate_yen': holidayDayRateYen,
  };
}

class CompanyRateSettingsRepository {
  CompanyRateSettingsRepository._(SupabaseClient client)
      : _client = client, _actor = client.auth.currentUser?.id;
  @visibleForTesting
  CompanyRateSettingsRepository.forTesting(SupabaseClient client)
      : _client = client, _actor = client.auth.currentUser?.id;

  final SupabaseClient _client;
  final String? _actor;

  Future<dynamic> _defaultsCall(String name, Map<String, dynamic> params) async {
    final session = _client.auth.currentSession;
    if (_actor == null || session == null || session.isExpired ||
        session.user.id != _actor) {
      throw StateError('ログイン情報が変わりました。画面を開き直してください。');
    }
    final token = session.accessToken;
    final result = await _client.rpc(name, params: params)
        .setHeader('Authorization', 'Bearer $token')
        .timeout(const Duration(seconds: 15));
    if (_client.auth.currentUser?.id != _actor ||
        _client.auth.currentSession?.accessToken != token) {
      throw StateError('保存状態を再読み込みして確認してください。');
    }
    return result;
  }

  CompanyRateSettings _defaultsResult(Object? raw, String companyId) {
    if (raw is! Map || raw['company_id'] != companyId ||
        raw['contract_version'] != 1) {
      throw StateError('会社の設定対象を確認できません。');
    }
    for (final key in const ['tax_rate', 'welfare_rate',
      'overtime_hour_rate_yen', 'early_hour_rate_yen',
      'night_hour_rate_yen', 'holiday_day_rate_yen']) {
      final value = raw[key];
      final rate = key == 'tax_rate' || key == 'welfare_rate';
      if (value is! num || !value.isFinite || value < 0 ||
          (rate ? value > 100 : value > 2147483647 || value != value.round())) {
        throw StateError('会社の設定値を確認できません。');
      }
    }
    return CompanyRateSettings.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<CompanyRateSettings> loadDefaults(String companyId) async =>
      _defaultsResult(await _defaultsCall('read_company_rate_defaults',
        {'p_company_id': companyId}), companyId);

  Future<CompanyRateSettings> saveDefaults({
    required CompanyRateSettings expected,
    required double taxRate,
    required double welfareRate,
    required int overtimeHourRateYen,
    required int earlyHourRateYen,
    required int nightHourRateYen,
    required int holidayDayRateYen,
  }) async {
    final companyId = expected.companyId;
    if (companyId == null || companyId.isEmpty) {
      throw StateError('会社情報を確認できません。');
    }
    final values = {
      'tax_rate': taxRate, 'welfare_rate': welfareRate,
      'overtime_hour_rate_yen': overtimeHourRateYen,
      'early_hour_rate_yen': earlyHourRateYen,
      'night_hour_rate_yen': nightHourRateYen,
      'holiday_day_rate_yen': holidayDayRateYen,
    };
    final saved = _defaultsResult(await _defaultsCall('save_company_rate_defaults', {
      'p_company_id': companyId, 'p_expected': expected.defaultsValues,
      'p_values': values,
    }), companyId);
    if (values.entries.any((entry) => saved.defaultsValues[entry.key] != entry.value)) {
      throw StateError('保存結果を確認できません。再読み込みしてください。');
    }
    return saved;
  }

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
      'save_company_rate_settings_with_units',
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

