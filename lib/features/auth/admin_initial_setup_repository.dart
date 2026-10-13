import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AdminInitialSetupState {
  const AdminInitialSetupState({
    required this.required,
    required this.completed,
    required this.personalProfileCompleted,
    required this.companyProfileCompleted,
    required this.companyDocumentsReviewed,
    required this.qualificationSettingsReviewed,
    required this.employeeRegistrationReviewed,
    required this.initialRegistrationReviewed,
  });

  final bool required;
  final bool completed;
  final bool personalProfileCompleted;
  final bool companyProfileCompleted;
  final bool companyDocumentsReviewed;
  final bool qualificationSettingsReviewed;
  final bool employeeRegistrationReviewed;
  final bool initialRegistrationReviewed;

  factory AdminInitialSetupState.fromMap(Map<String, dynamic> row) {
    return AdminInitialSetupState(
      required: row['required'] == true,
      completed: row['completed'] == true,
      personalProfileCompleted: row['personal_profile_completed'] == true,
      companyProfileCompleted: row['company_profile_completed'] == true,
      companyDocumentsReviewed: row['company_documents_reviewed'] == true,
      qualificationSettingsReviewed:
          row['qualification_settings_reviewed'] == true,
      employeeRegistrationReviewed:
          row['employee_registration_reviewed'] == true,
      initialRegistrationReviewed:
          row['initial_registration_reviewed'] == true,
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
        personalProfileCompleted: true,
        companyProfileCompleted: true,
        companyDocumentsReviewed: true,
        qualificationSettingsReviewed: true,
        employeeRegistrationReviewed: true,
        initialRegistrationReviewed: true,
      );
    }
    return AdminInitialSetupState.fromMap(
      Map<String, dynamic>.from(value),
    );
  }

  Future<void> markStep(String step) async {
    await _client.rpc(
      'mark_admin_initial_setup_step',
      params: {'p_step': step},
    );
  }
}
