import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../domain/rate_formula_settings.dart';

class AdminSiteFinancialRecord {
  const AdminSiteFinancialRecord({
    required this.siteId,
    required this.siteName,
    required this.status,
    required this.workerDailyRateYen,
    required this.overtimeHourRateYen,
    required this.earlyHourRateYen,
    required this.nightHourRateYen,
    required this.billingUnitPriceYen,
    required this.billingOvertimeHourRateYen,
    required this.billingEarlyHourRateYen,
    required this.billingMonthlyRateYen,
    required this.billingSquareMeterUnitPriceYen,
    required this.billingSquareMeterQuantity,
    required this.billingContractAmountYen,
    required this.welfareRate,
    this.billingAllowance1Name = '',
    this.billingAllowance1AmountYen = 0,
    this.billingAllowance2Name = '',
    this.billingAllowance2AmountYen = 0,
    this.billingAllowance3Name = '',
    this.billingAllowance3AmountYen = 0,
    this.workerFormulas = const RateFormulaSettings(),
    this.billingFormulas = const RateFormulaSettings(),
    this.workerRateOverrides = const {},
    this.billingRateOverrides = const {},
  });

  final String siteId;
  final String siteName;
  final String status;
  final int workerDailyRateYen;
  final int overtimeHourRateYen;
  final int earlyHourRateYen;
  final int nightHourRateYen;
  final int billingUnitPriceYen;
  final int billingOvertimeHourRateYen;
  final int billingEarlyHourRateYen;
  final int billingMonthlyRateYen;
  final int billingSquareMeterUnitPriceYen;
  final double billingSquareMeterQuantity;
  final int billingContractAmountYen;
  final double welfareRate;
  final String billingAllowance1Name;
  final int billingAllowance1AmountYen;
  final String billingAllowance2Name;
  final int billingAllowance2AmountYen;
  final String billingAllowance3Name;
  final int billingAllowance3AmountYen;
  final RateFormulaSettings workerFormulas;
  final RateFormulaSettings billingFormulas;
  final Map<String, int> workerRateOverrides;
  final Map<String, int> billingRateOverrides;

  int workerRate(String key) {
    final direct = workerRateOverrides[key] ?? 0;
    final daily = workerDailyRateYen;
    final calculated = switch (key) {
      'overtime' => workerFormulas.overtime(daily),
      'early' => workerFormulas.early(daily),
      'night' => workerFormulas.night(daily),
      'night_overtime' => workerFormulas.nightOvertime(daily),
      'holiday' => workerFormulas.holiday(daily),
      'holiday_overtime' => workerFormulas.holidayOvertime(daily),
      'holiday_night' => workerFormulas.holidayNight(daily),
      'holiday_night_overtime' =>
        workerFormulas.holidayNightOvertime(daily),
      _ => 0,
    };
    return effectiveRate(direct, calculated);
  }

  int billingRate(String key) {
    final direct = billingRateOverrides[key] ?? 0;
    final daily = billingUnitPriceYen;
    final calculated = switch (key) {
      'overtime' => billingFormulas.overtime(daily),
      'early' => billingFormulas.early(daily),
      'night' => billingFormulas.night(daily),
      'night_overtime' => billingFormulas.nightOvertime(daily),
      'holiday' => billingFormulas.holiday(daily),
      'holiday_overtime' => billingFormulas.holidayOvertime(daily),
      'holiday_night' => billingFormulas.holidayNight(daily),
      'holiday_night_overtime' =>
        billingFormulas.holidayNightOvertime(daily),
      _ => 0,
    };
    return effectiveRate(direct, calculated);
  }

  bool get hasManDayBilling => billingUnitPriceYen > 0;
  bool get hasMonthlyBilling => billingMonthlyRateYen > 0;
  bool get hasSquareMeterBilling =>
      billingSquareMeterUnitPriceYen > 0 && billingSquareMeterQuantity > 0;
  bool get hasContractBilling => billingContractAmountYen > 0;

  int get billingMethodCount =>
      (hasManDayBilling ? 1 : 0) +
      (hasMonthlyBilling ? 1 : 0) +
      (hasSquareMeterBilling ? 1 : 0) +
      (hasContractBilling ? 1 : 0);

  bool get billingConfigured => billingMethodCount == 1;

  String get billingMethodLabel {
    if (hasManDayBilling) return '1日単価';
    if (hasMonthlyBilling) return '月単価';
    if (hasSquareMeterBilling) return '平米';
    if (hasContractBilling) return '請負';
    return '未設定';
  }

  int get fixedBillingBaseAmountYen {
    if (hasSquareMeterBilling) {
      return (billingSquareMeterUnitPriceYen * billingSquareMeterQuantity)
          .round();
    }
    if (hasContractBilling) return billingContractAmountYen;
    return 0;
  }
}

class AdminSiteFinancialRepository {
  AdminSiteFinancialRepository._(this._client);

  final SupabaseClient _client;

  static AdminSiteFinancialRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AdminSiteFinancialRepository._(client);
  }

  Future<({String companyId, Map<String, dynamic> permissions})>
      _access() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    final raw = await _client.rpc('current_feature_permissions');
    final permissions = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};

    return (
      companyId: rows.first['company_id'] as String,
      permissions: permissions,
    );
  }

  Future<bool> canManage() async {
    final value = await _access();
    return value.permissions['can_manage_admin_site_data'] == true;
  }

  Future<String> _companyIdForView() async {
    final value = await _access();
    final canView =
        value.permissions['can_view_admin_site_data'] == true ||
        value.permissions['can_manage_admin_site_data'] == true;
    if (!canView) {
      throw StateError('管理者用現場データを見る権限がありません。');
    }
    return value.companyId;
  }

  Future<String> _companyIdForManage() async {
    final value = await _access();
    if (value.permissions['can_manage_admin_site_data'] != true) {
      throw StateError('管理者用現場データを変更する権限がありません。');
    }
    return value.companyId;
  }

  Future<List<AdminSiteFinancialRecord>> loadAll() async {
    final companyId = await _companyIdForView();

    final sites = await _client
        .from('sites')
        .select('id, name, status')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

    final settings = await _client
        .from('site_financial_settings')
        .select(
          'site_id, worker_daily_rate_yen, overtime_hour_rate_yen, '
          'early_hour_rate_yen, night_hour_rate_yen, billing_unit_price_yen, '
          'billing_overtime_hour_rate_yen, billing_early_hour_rate_yen, '
          'billing_monthly_rate_yen, '
          'billing_square_meter_unit_price_yen, '
          'billing_square_meter_quantity, billing_contract_amount_yen, '
          'welfare_rate, billing_allowance_1_name, '
          'billing_allowance_1_amount_yen, billing_allowance_2_name, '
          'billing_allowance_2_amount_yen, billing_allowance_3_name, '
          'billing_allowance_3_amount_yen, worker_rate_formula, '
          'worker_rate_overrides, billing_rate_formula, billing_rate_overrides',
        )
        .eq('company_id', companyId);

    final bySite = <String, Map<String, dynamic>>{
      for (final raw in settings)
        raw['site_id'].toString(): Map<String, dynamic>.from(raw),
    };

    return sites.map<AdminSiteFinancialRecord>((raw) {
      final row = Map<String, dynamic>.from(raw);
      final siteId = row['id'].toString();
      final s = bySite[siteId] ?? const <String, dynamic>{};

      return AdminSiteFinancialRecord(
        siteId: siteId,
        siteName: row['name']?.toString() ?? '',
        status: row['status']?.toString() ?? 'preparation',
        workerDailyRateYen:
            (s['worker_daily_rate_yen'] as num?)?.toInt() ?? 0,
        overtimeHourRateYen:
            (s['overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
        earlyHourRateYen:
            (s['early_hour_rate_yen'] as num?)?.toInt() ?? 0,
        nightHourRateYen:
            (s['night_hour_rate_yen'] as num?)?.toInt() ?? 0,
        billingUnitPriceYen:
            (s['billing_unit_price_yen'] as num?)?.toInt() ?? 0,
        billingOvertimeHourRateYen:
            (s['billing_overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
        billingEarlyHourRateYen:
            (s['billing_early_hour_rate_yen'] as num?)?.toInt() ?? 0,
        billingMonthlyRateYen:
            (s['billing_monthly_rate_yen'] as num?)?.toInt() ?? 0,
        billingSquareMeterUnitPriceYen:
            (s['billing_square_meter_unit_price_yen'] as num?)?.toInt() ?? 0,
        billingSquareMeterQuantity:
            (s['billing_square_meter_quantity'] as num?)?.toDouble() ?? 0,
        billingContractAmountYen:
            (s['billing_contract_amount_yen'] as num?)?.toInt() ?? 0,
        welfareRate: (s['welfare_rate'] as num?)?.toDouble() ?? 0,
        billingAllowance1Name:
            s['billing_allowance_1_name']?.toString() ?? '',
        billingAllowance1AmountYen:
            (s['billing_allowance_1_amount_yen'] as num?)?.toInt() ?? 0,
        billingAllowance2Name:
            s['billing_allowance_2_name']?.toString() ?? '',
        billingAllowance2AmountYen:
            (s['billing_allowance_2_amount_yen'] as num?)?.toInt() ?? 0,
        billingAllowance3Name:
            s['billing_allowance_3_name']?.toString() ?? '',
        billingAllowance3AmountYen:
            (s['billing_allowance_3_amount_yen'] as num?)?.toInt() ?? 0,
        workerFormulas: RateFormulaSettings.fromMap(s['worker_rate_formula']),
        billingFormulas:
            RateFormulaSettings.fromMap(s['billing_rate_formula']),
        workerRateOverrides: _rateOverrides(s['worker_rate_overrides']),
        billingRateOverrides: _rateOverrides(s['billing_rate_overrides']),
      );
    }).toList();
  }

  Future<void> save(AdminSiteFinancialRecord record) async {
    final companyId = await _companyIdForManage();

    await _client.from('site_financial_settings').upsert({
      'site_id': record.siteId,
      'company_id': companyId,
      'worker_daily_rate_yen': record.workerDailyRateYen,
      'overtime_hour_rate_yen': record.overtimeHourRateYen,
      'early_hour_rate_yen': record.earlyHourRateYen,
      'night_hour_rate_yen': record.nightHourRateYen,
      'billing_unit_price_yen': record.billingUnitPriceYen,
      'billing_overtime_hour_rate_yen': record.billingOvertimeHourRateYen,
      'billing_early_hour_rate_yen': record.billingEarlyHourRateYen,
      'billing_monthly_rate_yen': record.billingMonthlyRateYen,
      'billing_square_meter_unit_price_yen':
          record.billingSquareMeterUnitPriceYen,
      'billing_square_meter_quantity': record.billingSquareMeterQuantity,
      'billing_contract_amount_yen': record.billingContractAmountYen,
      'welfare_rate': record.welfareRate,
      'billing_allowance_1_name': record.billingAllowance1Name.trim().isEmpty
          ? null
          : record.billingAllowance1Name.trim(),
      'billing_allowance_1_amount_yen': record.billingAllowance1AmountYen,
      'billing_allowance_2_name': record.billingAllowance2Name.trim().isEmpty
          ? null
          : record.billingAllowance2Name.trim(),
      'billing_allowance_2_amount_yen': record.billingAllowance2AmountYen,
      'billing_allowance_3_name': record.billingAllowance3Name.trim().isEmpty
          ? null
          : record.billingAllowance3Name.trim(),
      'billing_allowance_3_amount_yen': record.billingAllowance3AmountYen,
      'worker_rate_formula': record.workerFormulas.toMap(),
      'worker_rate_overrides': record.workerRateOverrides,
      'billing_rate_formula': record.billingFormulas.toMap(),
      'billing_rate_overrides': record.billingRateOverrides,
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
  static Map<String, int> _rateOverrides(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      final parsed = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '') ?? 0;
      result[entry.key.toString()] = parsed;
    }
    return result;
  }

}
