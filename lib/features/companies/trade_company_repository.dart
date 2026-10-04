import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

enum TradeCompanyPageMode { customer, subcontractor }

class TradeCompanyRecord {
  const TradeCompanyRecord({
    required this.id,
    required this.name,
    required this.tradeRole,
    required this.linkStatus,
    required this.postalCode,
    required this.address,
    required this.phone,
    required this.email,
    required this.corporateNumber,
    required this.notes,
    required this.contractMethod,
    required this.dailyRateYen,
    required this.monthlyRateYen,
    required this.squareMeterUnitPriceYen,
    required this.squareMeterQuantity,
    required this.contractAmountYen,
  });

  final String id;
  final String name;
  final String tradeRole;
  final String linkStatus;
  final String postalCode;
  final String address;
  final String phone;
  final String email;
  final String corporateNumber;
  final String notes;
  final String contractMethod;
  final int dailyRateYen;
  final int monthlyRateYen;
  final int squareMeterUnitPriceYen;
  final double squareMeterQuantity;
  final int contractAmountYen;

  bool get isCustomer => tradeRole == 'customer' || tradeRole == 'both';
  bool get isSubcontractor =>
      tradeRole == 'subcontractor' || tradeRole == 'both';

  factory TradeCompanyRecord.fromJson(Map<String, dynamic> row) {
    return TradeCompanyRecord(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      tradeRole: row['trade_role']?.toString() ?? 'customer',
      linkStatus: row['link_status']?.toString() ?? 'local',
      postalCode: row['postal_code']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      corporateNumber: row['corporate_number']?.toString() ?? '',
      notes: row['notes']?.toString() ?? '',
      contractMethod: row['contract_method']?.toString() ?? 'none',
      dailyRateYen: (row['daily_rate_yen'] as num?)?.toInt() ?? 0,
      monthlyRateYen: (row['monthly_rate_yen'] as num?)?.toInt() ?? 0,
      squareMeterUnitPriceYen:
          (row['square_meter_unit_price_yen'] as num?)?.toInt() ?? 0,
      squareMeterQuantity:
          (row['square_meter_quantity'] as num?)?.toDouble() ?? 0,
      contractAmountYen: (row['contract_amount_yen'] as num?)?.toInt() ?? 0,
    );
  }
}

class TradeCompanyLinkCandidate {
  const TradeCompanyLinkCandidate({
    required this.companyId,
    required this.companyName,
    required this.phone,
    required this.address,
    required this.corporateNumber,
    required this.matchScore,
  });

  final String companyId;
  final String companyName;
  final String phone;
  final String address;
  final String corporateNumber;
  final int matchScore;

  factory TradeCompanyLinkCandidate.fromJson(Map<String, dynamic> row) {
    return TradeCompanyLinkCandidate(
      companyId: row['company_id']?.toString() ?? '',
      companyName: row['company_name']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      address: row['address']?.toString() ?? '',
      corporateNumber: row['corporate_number']?.toString() ?? '',
      matchScore: (row['match_score'] as num?)?.toInt() ??
          int.tryParse(row['match_score']?.toString() ?? '') ??
          0,
    );
  }
}

class TradeCompanyRepository {
  TradeCompanyRepository._(this._client);

  final SupabaseClient _client;

  static TradeCompanyRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return TradeCompanyRepository._(client);
  }

  Future<List<TradeCompanyRecord>> loadAll() async {
    final raw = await _client.rpc('trade_company_workspace');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyRecord.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<String> saveCompany({
    String? id,
    required String name,
    required String tradeRole,
    String? postalCode,
    String? address,
    String? phone,
    String? email,
    String? corporateNumber,
    String? notes,
  }) async {
    final value = await _client.rpc(
      'save_trade_company',
      params: {
        'p_id': id,
        'p_name': name,
        'p_trade_role': tradeRole,
        'p_postal_code': postalCode,
        'p_address': address,
        'p_phone': phone,
        'p_email': email,
        'p_corporate_number': corporateNumber,
        'p_notes': notes,
      },
    );
    return value?.toString() ?? '';
  }

  Future<void> saveContract({
    required String tradeCompanyId,
    required String contractMethod,
    required int dailyRateYen,
    required int monthlyRateYen,
    required int squareMeterUnitPriceYen,
    required double squareMeterQuantity,
    required int contractAmountYen,
  }) async {
    await _client.rpc(
      'save_trade_company_contract',
      params: {
        'p_trade_company_id': tradeCompanyId,
        'p_contract_method': contractMethod,
        'p_daily_rate_yen': dailyRateYen,
        'p_monthly_rate_yen': monthlyRateYen,
        'p_square_meter_unit_price_yen': squareMeterUnitPriceYen,
        'p_square_meter_quantity': squareMeterQuantity,
        'p_contract_amount_yen': contractAmountYen,
      },
    );
  }

  Future<List<TradeCompanyLinkCandidate>> linkCandidates(String id) async {
    final raw = await _client.rpc(
      'trade_company_link_candidates',
      params: {'p_trade_company_id': id},
    );
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyLinkCandidate.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  Future<void> confirmLink({
    required String tradeCompanyId,
    required String linkedCompanyId,
  }) async {
    await _client.rpc(
      'confirm_trade_company_link',
      params: {
        'p_trade_company_id': tradeCompanyId,
        'p_linked_company_id': linkedCompanyId,
      },
    );
  }

  Future<void> selectCalculationSource({
    required String siteId,
    required String outputType,
    required String tradeCompanyId,
    required String source,
  }) async {
    await _client.rpc(
      'select_site_calculation_source',
      params: {
        'p_site_id': siteId,
        'p_output_type': outputType,
        'p_trade_company_id': tradeCompanyId,
        'p_source': source,
      },
    );
  }
}


class TradeCompanyCalculationConflict {
  const TradeCompanyCalculationConflict({
    required this.siteId,
    required this.siteName,
    required this.outputType,
    required this.siteSettingConfigured,
    required this.tradeCompanySettingConfigured,
    required this.conflict,
    required this.selectedSource,
  });

  final String siteId;
  final String siteName;
  final String outputType;
  final bool siteSettingConfigured;
  final bool tradeCompanySettingConfigured;
  final bool conflict;
  final String? selectedSource;

  String get outputLabel => switch (outputType) {
        'invoice' => '請求書',
        'payment_certificate' => '支払証明書',
        'payroll' => '給料明細',
        _ => outputType,
      };

  factory TradeCompanyCalculationConflict.fromJson(
    Map<String, dynamic> row,
  ) {
    return TradeCompanyCalculationConflict(
      siteId: row['site_id']?.toString() ?? '',
      siteName: row['site_name']?.toString() ?? '',
      outputType: row['output_type']?.toString() ?? '',
      siteSettingConfigured: row['site_setting_configured'] == true,
      tradeCompanySettingConfigured:
          row['trade_company_setting_configured'] == true,
      conflict: row['conflict'] == true,
      selectedSource: row['selected_source']?.toString(),
    );
  }
}

extension TradeCompanyConflictRepository on TradeCompanyRepository {
  Future<List<TradeCompanyCalculationConflict>> calculationConflicts(
    String tradeCompanyId,
  ) async {
    final raw = await _client.rpc(
      'trade_company_calculation_conflicts',
      params: {'p_trade_company_id': tradeCompanyId},
    );
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          TradeCompanyCalculationConflict.fromJson(
            Map<String, dynamic>.from(item),
          ),
    ];
  }
}
