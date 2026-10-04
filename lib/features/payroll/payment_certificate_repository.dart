import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

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
  });

  final String partnerCompanyId;
  final String partnerCompanyName;
  final int dailyRateYen;
  final int overtimeHourRateYen;
  final int earlyHourRateYen;
  final int nightHourRateYen;
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
    final companyId = await _companyId();
    final partners = await _client
        .from('partner_companies')
        .select('id,name')
        .eq('company_id', companyId)
        .eq('status', 'active')
        .order('name');

    final settings = await _client
        .from('partner_payment_settings')
        .select()
        .eq('company_id', companyId);

    final byPartner = <String, Map<String, dynamic>>{
      for (final raw in settings)
        raw['partner_company_id'].toString(): Map<String, dynamic>.from(raw),
    };

    return [
      for (final partner in partners)
        PartnerPaymentSetting(
          partnerCompanyId: partner['id'].toString(),
          partnerCompanyName: partner['name']?.toString() ?? '',
          dailyRateYen:
              (byPartner[partner['id'].toString()]?['daily_rate_yen'] as num?)
                      ?.toInt() ??
                  0,
          overtimeHourRateYen: (byPartner[partner['id'].toString()]
                      ?['overtime_hour_rate_yen'] as num?)
                  ?.toInt() ??
              0,
          earlyHourRateYen: (byPartner[partner['id'].toString()]
                      ?['early_hour_rate_yen'] as num?)
                  ?.toInt() ??
              0,
          nightHourRateYen: (byPartner[partner['id'].toString()]
                      ?['night_hour_rate_yen'] as num?)
                  ?.toInt() ??
              0,
        ),
    ];
  }

  Future<void> saveSetting(PartnerPaymentSetting value) async {
    final companyId = await _companyId();
    await _client.from('partner_payment_settings').upsert({
      'company_id': companyId,
      'partner_company_id': value.partnerCompanyId,
      'daily_rate_yen': value.dailyRateYen,
      'overtime_hour_rate_yen': value.overtimeHourRateYen,
      'early_hour_rate_yen': value.earlyHourRateYen,
      'night_hour_rate_yen': value.nightHourRateYen,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
