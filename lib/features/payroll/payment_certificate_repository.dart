import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../domain/rate_formula_settings.dart';

class PaymentCertificateLine {
  const PaymentCertificateLine({
    required this.siteName,
    required this.workContent,
    required this.quantityLabel,
    required this.unitPriceYen,
    required this.amountYen,
  });

  final String siteName;
  final String workContent;
  final String quantityLabel;
  final int unitPriceYen;
  final int amountYen;
}

class PaymentCertificateRecord {
  const PaymentCertificateRecord({
    required this.id,
    required this.partnerCompanyName,
    required this.periodStart,
    required this.periodEnd,
    required this.grossAmount,
    required this.deductions,
    required this.netAmount,
    required this.status,
    required this.revision,
    this.payerCompanyName = '',
    this.payerPostalCode = '',
    this.payerAddress = '',
    this.payerPhone = '',
    this.payerFax = '',
    this.lines = const [],
  });

  final String id;
  final String partnerCompanyName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int grossAmount;
  final int deductions;
  final int netAmount;
  final String status;
  final int revision;
  final String payerCompanyName;
  final String payerPostalCode;
  final String payerAddress;
  final String payerPhone;
  final String payerFax;
  final List<PaymentCertificateLine> lines;

  String get monthLabel => '${periodStart.year}年${periodStart.month}月';
}

class PartnerPaymentSetting {
  const PartnerPaymentSetting({
    required this.partnerCompanyId,
    required this.partnerCompanyName,
    required this.dailyRateYen,
    required this.overtimeHourRateYen,
    required this.earlyHourRateYen,
    required this.nightHourRateYen,
    this.nightDayRateYen = 0,
    this.nightOvertimeHourRateYen = 0,
    this.holidayDayRateYen = 0,
    this.holidayOvertimeHourRateYen = 0,
    this.holidayNightDayRateYen = 0,
    this.holidayNightOvertimeHourRateYen = 0,
    this.formulas = const RateFormulaSettings(),
    this.hourlyBaseRateYen = 0,
    this.allowances = const [],
    this.welfareRate = 0,
    this.taxRate = 10,
  });

  final String partnerCompanyId;
  final String partnerCompanyName;
  final int dailyRateYen;
  final int overtimeHourRateYen;
  final int earlyHourRateYen;
  final int nightHourRateYen;
  final int nightDayRateYen;
  final int nightOvertimeHourRateYen;
  final int holidayDayRateYen;
  final int holidayOvertimeHourRateYen;
  final int holidayNightDayRateYen;
  final int holidayNightOvertimeHourRateYen;
  final RateFormulaSettings formulas;
  final int hourlyBaseRateYen;
  final List<PaymentAllowanceSetting> allowances;
  final double welfareRate;
  final double taxRate;

  int get formulaBaseRateYen => formulas.hourlyBase && hourlyBaseRateYen > 0
      ? hourlyBaseRateYen
      : dailyRateYen;

  int get overtimeRate =>
      effectiveRate(overtimeHourRateYen, formulas.overtime(formulaBaseRateYen));
  int get earlyRate =>
      effectiveRate(earlyHourRateYen, formulas.early(formulaBaseRateYen));
  int get nightDayRate =>
      effectiveRate(nightDayRateYen, formulas.night(formulaBaseRateYen));
  int get nightOvertimeRate => effectiveRate(
        nightOvertimeHourRateYen,
        formulas.nightOvertime(formulaBaseRateYen),
      );
  int get holidayDayRate =>
      effectiveRate(holidayDayRateYen, formulas.holiday(formulaBaseRateYen));
  int get holidayOvertimeRate => effectiveRate(
        holidayOvertimeHourRateYen,
        formulas.holidayOvertime(formulaBaseRateYen),
      );
  int get holidayNightDayRate => effectiveRate(
        holidayNightDayRateYen,
        formulas.holidayNight(formulaBaseRateYen),
      );
  int get holidayNightOvertimeRate => effectiveRate(
        holidayNightOvertimeHourRateYen,
        formulas.holidayNightOvertime(formulaBaseRateYen),
      );
}

class PaymentAllowanceSetting {
  const PaymentAllowanceSetting({
    required this.name,
    required this.amountYen,
  });

  final String name;
  final int amountYen;
}

class PaymentCertificateRepository {
  PaymentCertificateRepository._(this._client);

  final SupabaseClient _client;

  static PaymentCertificateRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PaymentCertificateRepository._(client);
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'].toString();
  }

  Future<List<PaymentCertificateRecord>> loadCertificates() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('payment_certificates')
        .select(
          'id,period_start,period_end,gross_amount,deductions,net_amount,status,revision,partner_companies(name)',
        )
        .eq('company_id', companyId)
        .order('period_start', ascending: false);

    final companyRows = await _client
        .from('companies')
        .select('name,postal_code,address,phone,fax')
        .eq('id', companyId)
        .limit(1);
    final company = companyRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(companyRows.first);

    final result = <PaymentCertificateRecord>[];
    for (final raw in rows) {
      final id = raw['id']?.toString() ?? '';
      final detailRaw = await _client.rpc(
        'payment_certificate_detail_rows',
        params: {'p_certificate_id': id},
      );
      final lines = <PaymentCertificateLine>[];
      if (detailRaw is List) {
        for (final value in detailRaw) {
          if (value is! Map) continue;
          final row = Map<String, dynamic>.from(value);
          lines.add(
            PaymentCertificateLine(
              siteName: row['site_name']?.toString() ?? '',
              workContent: row['work_content']?.toString() ?? '',
              quantityLabel: row['quantity_label']?.toString() ?? '',
              unitPriceYen: (row['unit_price_yen'] as num?)?.toInt() ?? 0,
              amountYen: (row['amount_yen'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }

      result.add(
        PaymentCertificateRecord(
          id: id,
          partnerCompanyName: raw['partner_companies'] is Map
              ? (raw['partner_companies']['name']?.toString() ?? '')
              : '',
          periodStart:
              DateTime.tryParse(raw['period_start']?.toString() ?? '') ??
                  DateTime.now(),
          periodEnd:
              DateTime.tryParse(raw['period_end']?.toString() ?? '') ??
                  DateTime.now(),
          grossAmount: (raw['gross_amount'] as num?)?.toInt() ?? 0,
          deductions: (raw['deductions'] as num?)?.toInt() ?? 0,
          netAmount: (raw['net_amount'] as num?)?.toInt() ?? 0,
          status: raw['status']?.toString() ?? 'draft',
          revision: (raw['revision'] as num?)?.toInt() ?? 1,
          payerCompanyName: company['name']?.toString() ?? '',
          payerPostalCode: company['postal_code']?.toString() ?? '',
          payerAddress: company['address']?.toString() ?? '',
          payerPhone: company['phone']?.toString() ?? '',
          payerFax: company['fax']?.toString() ?? '',
          lines: List.unmodifiable(lines),
        ),
      );
    }
    return result;
  }

  Future<List<PartnerPaymentSetting>> loadSettings() async {
    final raw = await _client.rpc('partner_payment_settings_workspace');
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if (value is Map)
          PartnerPaymentSetting(
            partnerCompanyId:
                value['partner_company_id']?.toString() ?? '',
            partnerCompanyName:
                value['partner_company_name']?.toString() ?? '',
            dailyRateYen:
                (value['daily_rate_yen'] as num?)?.toInt() ?? 0,
            overtimeHourRateYen:
                (value['overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
            earlyHourRateYen:
                (value['early_hour_rate_yen'] as num?)?.toInt() ?? 0,
            nightHourRateYen:
                (value['night_hour_rate_yen'] as num?)?.toInt() ?? 0,
            nightDayRateYen:
                (value['night_day_rate_yen'] as num?)?.toInt() ?? 0,
            nightOvertimeHourRateYen:
                (value['night_overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
            holidayDayRateYen:
                (value['holiday_day_rate_yen'] as num?)?.toInt() ?? 0,
            holidayOvertimeHourRateYen:
                (value['holiday_overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
            holidayNightDayRateYen:
                (value['holiday_night_day_rate_yen'] as num?)?.toInt() ?? 0,
            holidayNightOvertimeHourRateYen:
                (value['holiday_night_overtime_hour_rate_yen'] as num?)?.toInt() ?? 0,
            formulas: RateFormulaSettings.fromMap(value['rate_formula']),
            hourlyBaseRateYen: value['rate_formula'] is Map
                ? ((value['rate_formula']['hourly_rate_yen'] as num?)?.toInt() ?? 0)
                : 0,
            allowances: _allowances(value['allowances']),
            welfareRate: (value['welfare_rate'] as num?)?.toDouble() ?? 0,
            taxRate: (value['tax_rate'] as num?)?.toDouble() ?? 10,
          ),
    ].where((item) => item.partnerCompanyId.isNotEmpty).toList();
  }

  Future<void> saveSetting(PartnerPaymentSetting value) async {
    await _client.rpc(
      'save_partner_payment_setting',
      params: {
        'p_partner_company_id': value.partnerCompanyId,
        'p_daily_rate_yen': value.dailyRateYen,
        'p_overtime_hour_rate_yen': value.overtimeHourRateYen,
        'p_early_hour_rate_yen': value.earlyHourRateYen,
        'p_night_hour_rate_yen': value.nightHourRateYen,
        'p_night_day_rate_yen': value.nightDayRateYen,
        'p_night_overtime_hour_rate_yen': value.nightOvertimeHourRateYen,
        'p_holiday_day_rate_yen': value.holidayDayRateYen,
        'p_holiday_overtime_hour_rate_yen': value.holidayOvertimeHourRateYen,
        'p_holiday_night_day_rate_yen': value.holidayNightDayRateYen,
        'p_holiday_night_overtime_hour_rate_yen':
            value.holidayNightOvertimeHourRateYen,
        'p_rate_formula': value.formulas.toMap(
          hourlyRateYen: value.hourlyBaseRateYen,
        ),
        'p_allowances': [
          for (final item in value.allowances)
            {'name': item.name, 'amount_yen': item.amountYen},
        ],
        'p_welfare_rate': value.welfareRate,
        'p_tax_rate': value.taxRate,
      },
    );

    final refreshed = await loadSettings();
    final saved = refreshed.where(
      (item) => item.partnerCompanyId == value.partnerCompanyId,
    );
    if (saved.isEmpty) {
      throw StateError('支払証明書設定を保存できませんでした。');
    }
    final actual = saved.first;
    if (actual.dailyRateYen != value.dailyRateYen ||
        actual.overtimeHourRateYen != value.overtimeHourRateYen ||
        actual.earlyHourRateYen != value.earlyHourRateYen ||
        actual.nightHourRateYen != value.nightHourRateYen ||
        actual.nightDayRateYen != value.nightDayRateYen ||
        actual.nightOvertimeHourRateYen != value.nightOvertimeHourRateYen ||
        actual.holidayDayRateYen != value.holidayDayRateYen ||
        actual.holidayOvertimeHourRateYen != value.holidayOvertimeHourRateYen ||
        actual.holidayNightDayRateYen != value.holidayNightDayRateYen ||
        actual.holidayNightOvertimeHourRateYen !=
            value.holidayNightOvertimeHourRateYen) {
      throw StateError('支払証明書設定を保存できませんでした。');
    }
  }

  Future<PaymentCertificateRecord> previewForSetting(
    PartnerPaymentSetting value,
  ) async {
    final companyId = await _companyId();
    final companyRows = await _client
        .from('companies')
        .select('name,postal_code,address,phone,fax')
        .eq('id', companyId)
        .limit(1);
    final company = companyRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(companyRows.first);

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    final lines = <PaymentCertificateLine>[
      PaymentCertificateLine(
        siteName: '設定プレビュー',
        workContent: '通常作業',
        quantityLabel: '1',
        unitPriceYen: value.dailyRateYen,
        amountYen: value.dailyRateYen,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '残業 1時間',
        quantityLabel: '1',
        unitPriceYen: value.overtimeRate,
        amountYen: value.overtimeRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '早出 1時間',
        quantityLabel: '1',
        unitPriceYen: value.earlyRate,
        amountYen: value.earlyRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '夜勤 1日',
        quantityLabel: '1',
        unitPriceYen: value.nightDayRate,
        amountYen: value.nightDayRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '夜勤残業 1時間',
        quantityLabel: '1',
        unitPriceYen: value.nightOvertimeRate,
        amountYen: value.nightOvertimeRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '休日出勤 1日',
        quantityLabel: '1',
        unitPriceYen: value.holidayDayRate,
        amountYen: value.holidayDayRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '休日残業 1時間',
        quantityLabel: '1',
        unitPriceYen: value.holidayOvertimeRate,
        amountYen: value.holidayOvertimeRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '休日夜勤 1日',
        quantityLabel: '1',
        unitPriceYen: value.holidayNightDayRate,
        amountYen: value.holidayNightDayRate,
      ),
      PaymentCertificateLine(
        siteName: '〃',
        workContent: '休日夜勤残業 1時間',
        quantityLabel: '1',
        unitPriceYen: value.holidayNightOvertimeRate,
        amountYen: value.holidayNightOvertimeRate,
      ),
      for (final allowance in value.allowances)
        if (allowance.name.trim().isNotEmpty && allowance.amountYen > 0)
          PaymentCertificateLine(
            siteName: '〃',
            workContent: '（${allowance.name.trim()}）',
            quantityLabel: '1',
            unitPriceYen: allowance.amountYen,
            amountYen: allowance.amountYen,
          ),
    ];

    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.amountYen);
    final welfare = (subtotal * value.welfareRate / 100).round();
    if (welfare > 0) {
      lines.add(
        PaymentCertificateLine(
          siteName: '〃',
          workContent: '（福利厚生費）',
          quantityLabel: '',
          unitPriceYen: 0,
          amountYen: welfare,
        ),
      );
    }
    final preTax = subtotal + welfare;
    final tax = (preTax * value.taxRate / 100).round();
    if (tax > 0) {
      lines.add(
        PaymentCertificateLine(
          siteName: '〃',
          workContent: '（消費税）',
          quantityLabel: '',
          unitPriceYen: 0,
          amountYen: tax,
        ),
      );
    }
    final gross = preTax + tax;

    return PaymentCertificateRecord(
      id: 'settings-preview',
      partnerCompanyName: value.partnerCompanyName,
      periodStart: start,
      periodEnd: end,
      grossAmount: gross,
      deductions: 0,
      netAmount: gross,
      status: 'draft',
      revision: 1,
      payerCompanyName: company['name']?.toString() ?? '',
      payerPostalCode: company['postal_code']?.toString() ?? '',
      payerAddress: company['address']?.toString() ?? '',
      payerPhone: company['phone']?.toString() ?? '',
      payerFax: company['fax']?.toString() ?? '',
      lines: lines,
    );
  }
  static List<PaymentAllowanceSetting> _allowances(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map &&
            (item['name']?.toString().trim().isNotEmpty ?? false))
          PaymentAllowanceSetting(
            name: item['name'].toString().trim(),
            amountYen: (item['amount_yen'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

}
