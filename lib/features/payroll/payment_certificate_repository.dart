import '../shared/company_seal_current_preview.dart';
import '../../domain/expense_cost_direction_v2_candidate.dart';
import '../../domain/expense_payment_reader_candidate.dart';
import '../expenses/expense_document_repository.dart';
import '../expenses/expense_detail_pdf.dart';
import 'dart:async';
import '../../domain/company_seal_snapshot.dart';
import '../shared/trade_document_adjustment_repository.dart';
import '../../domain/expense_cost_snapshot.dart';
import '../../domain/trade_document_adjustment_snapshot.dart';
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
    this.isAgreementSnapshot = false,
    this.companySealSnapshot = CompanySealSnapshot.legacy,
    this.payerCompanySealEnabled = true,
    this.payerPostalCode = '',
    this.payerAddress = '',
    this.payerPhone = '',
    this.payerFax = '',
    this.partnerCompanyId = '',
    this.lines = const [],
    this.expenseCost = const ExpenseCostSnapshot.none(),
    this.directionalExpenseRead,
    this.documentAdjustments = const [],
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
  /// Document origin only; does not finalize a monthly certificate.
  final bool isAgreementSnapshot;
  final CompanySealSnapshot companySealSnapshot;
  final bool payerCompanySealEnabled;
  final String payerPostalCode;
  final String payerAddress;
  final String payerPhone;
  final String payerFax;
  final String partnerCompanyId;
  final List<PaymentCertificateLine> lines;
  final ExpenseCostSnapshot expenseCost;
  final List<SavedTradeDocumentAdjustment> documentAdjustments;
  final ExpensePaymentReadCandidate? directionalExpenseRead;
  bool get hasDirectionalExpense => directionalExpenseRead?.usesV2 == true;
  int get expenseExtraAmountYen => directionalExpenseRead?.directionalCost?.amountYen ?? expenseCost.amountYen;
  int get expenseLineDeltaYen => directionalExpenseRead?.expenseLineDeltaYen ?? expenseCost.amountYen;

  void verifyDirectionalExpense() {
    final read = directionalExpenseRead;
    if (read == null) return;
    final scope = read.directionalCost?.context;
    if (!read.usesV2 || expenseCost.isCurrent || scope == null ||
        scope.documentId != id || scope.subjectId != partnerCompanyId ||
        scope.documentRevision != revision ||
        scope.month != '${periodStart.year}-${periodStart.month.toString().padLeft(2, '0')}' ||
        read.periodStart != '${periodStart.year}-${periodStart.month.toString().padLeft(2, '0')}-${periodStart.day.toString().padLeft(2, '0')}' ||
        read.periodEnd != '${periodEnd.year}-${periodEnd.month.toString().padLeft(2, '0')}-${periodEnd.day.toString().padLeft(2, '0')}' ||
        read.grossYen != grossAmount || read.deductionsYen != deductions || read.netYen != netAmount) {
      throw StateError('方向付き経費と支払証明書が一致しません。');
    }
  }

  String get monthLabel => '${periodStart.year}年${periodStart.month}月';
  bool get isPreview => status == 'preview';
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
  const PaymentAllowanceSetting({required this.name, required this.amountYen});

  final String name;
  final int amountYen;
}

class PaymentCertificateRepository {
  PaymentCertificateRepository._(this._client, {this.enableExpenseDirectionV2 = false});
  PaymentCertificateRepository.forTesting(this._client, {this.enableExpenseDirectionV2 = false});
  final bool enableExpenseDirectionV2;

  final SupabaseClient _client;
  String? _loadedCompanyId;
  String? get loadedCompanyId => _loadedCompanyId;

  SupabaseTradeDocumentAdjustmentRepository createAdjustmentPort() =>
      SupabaseTradeDocumentAdjustmentRepository(_client);

  Future<bool> canAdjustLoadedCompany() async {
    final company = _loadedCompanyId, actor = _client.auth.currentUser?.id;
    if (company == null || actor == null) return false;
    final rows = await _client.from('company_members').select('role')
        .eq('company_id', company).eq('user_id', actor);
    return _client.auth.currentUser?.id == actor && rows.any((row) =>
        const ['owner', 'admin'].contains(row['role']));
  }

  static PaymentCertificateRepository? maybeCreate({bool enableExpenseDirectionV2 = false}) {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PaymentCertificateRepository._(client, enableExpenseDirectionV2: enableExpenseDirectionV2);
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

  Future<List<PaymentCertificateRecord>> loadCertificates({
    bool includeRegisteredPreviews = false,
  }) async {
    final lease = enableExpenseDirectionV2 ? _PaymentDirectionActorLease(_client) : null;
    try {
      final rows = await _loadCertificates(includeRegisteredPreviews: includeRegisteredPreviews);
      lease?.verify();
      return rows;
    } finally { lease?.dispose(); }
  }

  Future<bool> _directionCapability(String companyId) async {
    if (!enableExpenseDirectionV2) return false;
    final actor = _client.auth.currentUser?.id;
    if (actor == null) return false;
    final Object? raw;
    try {
      raw = await _client.rpc('expense_payment_direction_capability', params: {'p_company': companyId});
    } on PostgrestException { return false; }
    const keys = {'version','contract','company_id','actor_id','document_kind','max_source_version','read_enabled'};
    return _client.auth.currentUser?.id == actor && raw is Map && raw.length == keys.length &&
      raw.keys.every(keys.contains) && raw['version'] is int && raw['version'] == 1 &&
      raw['contract'] == 'expense_payment_direction_v2' && raw['company_id'] == companyId && raw['actor_id'] == actor &&
      raw['document_kind'] == 'paymentCertificate' && raw['max_source_version'] is int && raw['max_source_version'] == 2 && raw['read_enabled'] == true;
  }

  Future<List<PaymentCertificateRecord>> _loadCertificates({
    bool includeRegisteredPreviews = false,
  }) async {
    _loadedCompanyId = null;
    final companyId = await _companyId();
    final directionEnabled = await _directionCapability(companyId);
    var certificateQuery = _client
        .from('payment_certificates')
        .select(
          'id,company_id,partner_company_id,period_start,period_end,gross_amount,deductions,net_amount,status,revision,snapshot,partner_companies(name)',
        );
    if (enableExpenseDirectionV2) {
      certificateQuery = certificateQuery.setHeader('x-sko-payment-source-version', '2');
    }
    final rows = await certificateQuery
        .eq('company_id', companyId)
        .order('period_start', ascending: false);

    final companyRows = await _client
        .from('companies')
        .select('id,name,postal_code,address,phone,fax,company_seal_enabled,company_seal_style')
        .eq('id', companyId)
        .limit(1);
    var company = companyRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(companyRows.first);

    final result = <PaymentCertificateRecord>[];
    for (final raw in rows) {
      final id = raw['id']?.toString() ?? '';
      var detailQuery = _client.rpc(
        'payment_certificate_detail_rows',
        params: {'p_certificate_id': id},
      );
      if (enableExpenseDirectionV2) {
        detailQuery = detailQuery.setHeader('x-sko-payment-source-version', '2');
      }
      final detailRaw = await detailQuery;
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

      ExpensePaymentReadCandidate? directionRead;
      final snapshot = raw['snapshot'] is Map ? Map<String, dynamic>.from(raw['snapshot']) : <String,dynamic>{};
      if (snapshot.containsKey('expense_cost_direction_v2')) {
        if (!directionEnabled) throw StateError('方向付き経費の利用準備が整っていません。');
        final start = raw['period_start'];
        final end = raw['period_end'];
        if (start is! String || end is! String || start.length != 10 || raw['revision'] is! int) {
          throw StateError('支払証明書の対象期間・版を確認できません。');
        }
        final scope = ExpenseCostContext(kind: ExpenseCostDocumentKind.paymentCertificate,
          companyId: companyId, documentId: id, subjectId: raw['partner_company_id']?.toString() ?? '',
          month: start.substring(0,7), documentRevision: raw['revision'] as int);
        final detail = await _client.rpc('read_expense_document', params: {'p_kind':'paymentCertificate','p_document':id})
            .setHeader('x-sko-payment-source-version', '2');
        if (detail is! Map || detail['expense_cost_basis'] is! Map) throw StateError('経費の同版基礎金額を確認できません。');
        ExpenseDocumentDetails.parse(Map<String,dynamic>.from(detail), ExpenseDocument.paymentCertificate,
          id, DateTime.parse(start), revision: scope.documentRevision);
        final basis = detail['expense_cost_basis'] as Map;
        const basisKeys = {'company_id','document_id','subject_id','month','document_revision','gross_before_expense_yen','other_deductions_yen'};
        if (basis.length != basisKeys.length || !basis.keys.every(basisKeys.contains) ||
            basis['company_id'] != companyId || basis['document_id'] != id || basis['subject_id'] != scope.subjectId ||
            basis['month'] != scope.month || basis['document_revision'] is! int || basis['document_revision'] != scope.documentRevision ||
            basis['gross_before_expense_yen'] is! int || basis['other_deductions_yen'] is! int ||
            snapshot['expense_cost_basis'] is! Map ||
            (snapshot['expense_cost_basis'] as Map).length != basisKeys.length ||
            !basisKeys.every((key) => (snapshot['expense_cost_basis'] as Map)[key].runtimeType == basis[key].runtimeType && (snapshot['expense_cost_basis'] as Map)[key] == basis[key])) {
          throw StateError('経費の対象と基礎金額が一致しません。');
        }
        directionRead = ExpensePaymentReadCandidate.read(row: Map<String,dynamic>.from(raw), expected: scope,
          expectedPeriodStart: start, expectedPeriodEnd: end, legacyDetails: const [], v2ContractVerified: directionEnabled,
          v2Basis: ExpensePaymentBasisCandidate(context: scope, grossBeforeExpenseYen: basis['gross_before_expense_yen'] as int,
            otherDeductionsYen: basis['other_deductions_yen'] as int), v2ScopedDetails: detail['expense_cost_direction_v2']);
      }
      result.add(
        PaymentCertificateRecord(
          id: id,
          companySealSnapshot: CompanySealSnapshot.fromJson(
              raw['snapshot'] is Map
                  ? raw['snapshot']['company_seal_snapshot'] : null),
          partnerCompanyId: raw['partner_company_id']?.toString() ?? '',
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
          payerCompanySealEnabled: company['company_seal_enabled'] != false,
          payerPostalCode: company['postal_code']?.toString() ?? '',
          payerAddress: company['address']?.toString() ?? '',
          payerPhone: company['phone']?.toString() ?? '',
          payerFax: company['fax']?.toString() ?? '',
          lines: List.unmodifiable(lines),
          expenseCost: directionRead == null ? ExpenseCostSnapshot.parse(snapshot) : const ExpenseCostSnapshot.none(),
          directionalExpenseRead: directionRead,
          documentAdjustments: SavedTradeDocumentAdjustment.parse(snapshot),
        ),
      );
    }
    if (!includeRegisteredPreviews) {
      _loadedCompanyId = companyId;
      return result;
    }
    // The existing admin-scoped settings RPC includes registered companies even
    // without attendance. Previews are in-memory only; no certificate is saved.
    final List<PartnerPaymentSetting> settings;
    try {
      settings = await loadSettings();
    } on PostgrestException catch (error) {
      if (!isPreviewPermissionDenied(error)) rethrow;
      // Certificate read access is independent of settings administration.
      // Keep the records already authorized by RLS; do not grant previews.
      _loadedCompanyId = companyId;
      return result;
    }
    _loadedCompanyId = companyId;
    try {
      company = await companyWithCurrentUploadedSeal(_client, company, companyId);
    } catch (_) {
      // Current-preview metadata must not hide already authorized saved records.
      return result;
    }
    return withRegisteredCompanyPreviews(
      result,
      settings,
      company: company,
      month: DateTime.now(),
    );
  }

  static bool isPreviewPermissionDenied(PostgrestException error) =>
      error.code == '42501' ||
      (error.code == 'P0001' && error.message == '管理者のみ操作できます。');

  static List<PaymentCertificateRecord> withRegisteredCompanyPreviews(
    List<PaymentCertificateRecord> certificates,
    List<PartnerPaymentSetting> settings, {
    required Map<String, dynamic> company,
    required DateTime month,
  }) {
    final existing = certificates
        .where(
          (item) =>
              item.periodStart.year == month.year &&
              item.periodStart.month == month.month,
        )
        .map((item) => item.partnerCompanyId)
        .toSet();
    return [
      for (final setting in settings)
        if (!existing.contains(setting.partnerCompanyId))
          emptyPreview(setting, company: company, month: month),
      ...certificates,
    ];
  }

  static PaymentCertificateRecord emptyPreview(
    PartnerPaymentSetting setting, {
    required Map<String, dynamic> company,
    required DateTime month,
  }) => PaymentCertificateRecord(
    id: 'preview:${setting.partnerCompanyId}:${month.year}-${month.month}',
    companySealSnapshot: CompanySealSnapshot.forPreview(company),
    partnerCompanyId: setting.partnerCompanyId,
    partnerCompanyName: setting.partnerCompanyName,
    periodStart: DateTime(month.year, month.month, 1),
    periodEnd: DateTime(month.year, month.month + 1, 0),
    grossAmount: 0,
    deductions: 0,
    netAmount: 0,
    status: 'preview',
    revision: 0,
    payerCompanyName: company['name']?.toString() ?? '',
    payerCompanySealEnabled: company['company_seal_enabled'] != false,
    payerPostalCode: company['postal_code']?.toString() ?? '',
    payerAddress: company['address']?.toString() ?? '',
    payerPhone: company['phone']?.toString() ?? '',
    payerFax: company['fax']?.toString() ?? '',
    lines: [
      for (final label in [
        '通常作業',
        '残業',
        '早出',
        '夜勤',
        '夜勤残業',
        '休日出勤',
        '休日残業',
        '休日夜勤',
        '休日夜勤残業',
        for (final allowance in setting.allowances)
          if (allowance.name.trim().isNotEmpty) allowance.name.trim(),
        '福利厚生費',
        '消費税',
      ])
        PaymentCertificateLine(
          siteName: '',
          workContent: label,
          quantityLabel: '',
          unitPriceYen: 0,
          amountYen: 0,
        ),
    ],
  );

  Future<List<PartnerPaymentSetting>> loadSettings() async {
    final raw = await _client.rpc('partner_payment_settings_workspace');
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if (value is Map)
          PartnerPaymentSetting(
            partnerCompanyId: value['partner_company_id']?.toString() ?? '',
            partnerCompanyName: value['partner_company_name']?.toString() ?? '',
            dailyRateYen: (value['daily_rate_yen'] as num?)?.toInt() ?? 0,
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
                (value['holiday_night_overtime_hour_rate_yen'] as num?)
                    ?.toInt() ??
                0,
            formulas: RateFormulaSettings.fromMap(value['rate_formula']),
            hourlyBaseRateYen: value['rate_formula'] is Map
                ? ((value['rate_formula']['hourly_rate_yen'] as num?)
                          ?.toInt() ??
                      0)
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
        .select('id,name,postal_code,address,phone,fax,company_seal_enabled,company_seal_style')
        .eq('id', companyId)
        .limit(1);
    var company = companyRows.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(companyRows.first);

    company = await companyWithCurrentUploadedSeal(_client, company, companyId);
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
      companySealSnapshot: CompanySealSnapshot.forPreview(company),
      partnerCompanyName: value.partnerCompanyName,
      periodStart: start,
      periodEnd: end,
      grossAmount: gross,
      deductions: 0,
      netAmount: gross,
      status: 'draft',
      revision: 1,
      payerCompanyName: company['name']?.toString() ?? '',
      payerCompanySealEnabled: company['company_seal_enabled'] != false,
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

class _PaymentDirectionActorLease {
  _PaymentDirectionActorLease(this.client) : actor = client.auth.currentUser?.id {
    revoked = actor == null;
    subscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != actor) revoked = true;
    }, onError: (Object error) { revoked = true; });
  }
  final SupabaseClient client;
  final String? actor;
  late bool revoked;
  StreamSubscription<AuthState>? subscription;
  void verify() {
    if (revoked || client.auth.currentUser?.id != actor) {
      throw StateError('ログイン情報が変わりました。支払証明書を開き直してください。');
    }
  }
  void dispose() { subscription?.cancel(); }
}


