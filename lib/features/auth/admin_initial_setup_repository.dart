import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AdminInitialSetupState {
  const AdminInitialSetupState({
    required this.required,
    required this.completed,
    required this.companyProfileCompleted,
    required this.documentRequirementsReviewed,
    required this.firstSiteCompleted,
    required this.rateSettingsCompleted,
  });

  final bool required;
  final bool completed;
  final bool companyProfileCompleted;
  final bool documentRequirementsReviewed;
  final bool firstSiteCompleted;
  final bool rateSettingsCompleted;

  factory AdminInitialSetupState.fromMap(Map<String, dynamic> row) {
    return AdminInitialSetupState(
      required: row['required'] == true,
      completed: row['completed'] == true,
      companyProfileCompleted: row['company_profile_completed'] == true,
      documentRequirementsReviewed:
          row['document_requirements_reviewed'] == true,
      firstSiteCompleted: row['first_site_completed'] == true,
      rateSettingsCompleted: row['rate_settings_completed'] == true,
    );
  }
}

class AdminInitialSetupRepository {
  AdminInitialSetupRepository._(this._client);

  final SupabaseClient _client;

  static AdminInitialSetupRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return AdminInitialSetupRepository._(SupabaseBackend.client);
  }

  Future<AdminInitialSetupState> loadState() async {
    final value = await _client.rpc('admin_initial_setup_state');
    if (value is! Map) {
      return const AdminInitialSetupState(
        required: false,
        completed: true,
        companyProfileCompleted: true,
        documentRequirementsReviewed: true,
        firstSiteCompleted: true,
        rateSettingsCompleted: true,
      );
    }
    return AdminInitialSetupState.fromMap(
      Map<String, dynamic>.from(value),
    );
  }

  Future<void> markDocumentRequirementsReviewed() async {
    await _client.rpc('mark_initial_document_requirements_reviewed');
  }

  Future<String> saveInitialSite({
    required String siteName,
    required String customerName,
    required String address,
    required String nearestStation,
    required int billingUnitPriceYen,
  }) async {
    final value = await _client.rpc(
      'save_initial_site',
      params: {
        'p_site_name': siteName.trim(),
        'p_customer_name': customerName.trim(),
        'p_site_address': address.trim(),
        'p_nearest_station': nearestStation.trim(),
        'p_billing_unit_price_yen': billingUnitPriceYen,
      },
    );
    return value?.toString() ?? '';
  }

  Future<void> saveInitialRates({
    required double taxRate,
    required double welfareRate,
    required int overtimeHourRateYen,
    required int earlyHourRateYen,
    required int nightHourRateYen,
    required int holidayDayRateYen,
    required String allowance1Name,
    required int allowance1AmountYen,
    required String allowance2Name,
    required int allowance2AmountYen,
    required String allowance3Name,
    required int allowance3AmountYen,
  }) async {
    await _client.rpc(
      'save_initial_company_rates',
      params: {
        'p_tax_rate': taxRate,
        'p_welfare_rate': welfareRate,
        'p_overtime_hour_rate_yen': overtimeHourRateYen,
        'p_early_hour_rate_yen': earlyHourRateYen,
        'p_night_hour_rate_yen': nightHourRateYen,
        'p_holiday_day_rate_yen': holidayDayRateYen,
        'p_allowance_1_name':
            allowance1Name.trim().isEmpty ? null : allowance1Name.trim(),
        'p_allowance_1_amount_yen': allowance1AmountYen,
        'p_allowance_2_name':
            allowance2Name.trim().isEmpty ? null : allowance2Name.trim(),
        'p_allowance_2_amount_yen': allowance2AmountYen,
        'p_allowance_3_name':
            allowance3Name.trim().isEmpty ? null : allowance3Name.trim(),
        'p_allowance_3_amount_yen': allowance3AmountYen,
      },
    );
  }
}
