import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class EmployeeOnboardingState {
  const EmployeeOnboardingState({
    required this.inviteId,
    required this.companyId,
    required this.workerId,
    required this.name,
    required this.phone,
    required this.status,
    required this.passwordChanged,
  });

  final String inviteId;
  final String companyId;
  final String workerId;
  final String name;
  final String phone;
  final String status;
  final bool passwordChanged;

  bool get needsPrimaryPassword =>
      status == 'invited' || status == 'password_changed';
  bool get needsProfile => status == 'profile_pending';
  bool get awaitingApproval => status == 'approval_pending';
}

class SecureOnboardingRepository {
  SecureOnboardingRepository._(this._client);

  final SupabaseClient _client;

  static SecureOnboardingRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    return SecureOnboardingRepository._(SupabaseBackend.client);
  }

  User? get currentUser => _client.auth.currentUser;

  static String normalizeJapanesePhoneValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('+')) {
      return '+${trimmed.substring(1).replaceAll(RegExp(r'\D'), '')}';
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('81')) return '+$digits';
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+81${digits.substring(1)}';
    }
    return '+$digits';
  }

  static bool isSupportedJapaneseMobileValue(String raw) {
    final normalized = normalizeJapanesePhoneValue(raw);
    return normalized.length == 13 &&
        RegExp(r'^\+81(?:70|80|90)\d{8}').hasMatch(normalized);
  }

  String normalizeJapanesePhone(String raw) =>
      normalizeJapanesePhoneValue(raw);

  Future<bool> registerAdmin({
    required String phone,
    required String password,
  }) async {
    final normalized = normalizeJapanesePhone(phone);
    final response = await _client.auth.signUp(
      phone: normalized,
      password: password,
      channel: OtpChannel.sms,
      data: const {
        'sko_registration_type': 'admin',
      },
    );
    return response.session != null;
  }

  Future<void> resendSmsCode({required String phone}) async {
    await _client.auth.resend(
      type: OtpType.sms,
      phone: normalizeJapanesePhone(phone),
    );
  }

  Future<void> verifySmsCode({
    required String phone,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: normalizeJapanesePhone(phone),
      token: code.trim(),
    );
  }

  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      phone: normalizeJapanesePhone(phone),
      password: password,
    );
  }

  Future<void> requestPasswordResetSms({required String phone}) async {
    await _client.auth.signInWithOtp(
      phone: normalizeJapanesePhone(phone),
      shouldCreateUser: false,
      channel: OtpChannel.sms,
    );
  }

  Future<void> verifyPasswordResetSms({
    required String phone,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: normalizeJapanesePhone(phone),
      token: code.trim(),
    );
  }

  Future<void> updatePrimaryPassword(String password) async {
    if (password.length < 8) {
      throw StateError('password must be at least 8 characters');
    }
    await _client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  Future<EmployeeOnboardingState?> employeeOnboardingState() async {
    if (_client.auth.currentUser == null) return null;
    final value = await _client.rpc('employee_onboarding_state');
    if (value == null || value is! Map) return null;
    final row = Map<String, dynamic>.from(value);
    final inviteId = row['invite_id']?.toString() ?? '';
    if (inviteId.isEmpty) return null;
    return EmployeeOnboardingState(
      inviteId: inviteId,
      companyId: row['company_id']?.toString() ?? '',
      workerId: row['worker_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      phone: row['phone']?.toString() ?? '',
      status: row['status']?.toString() ?? 'invited',
      passwordChanged: row['password_changed_at'] != null,
    );
  }

  Future<void> setEmployeePrimaryPassword(String password) async {
    await updatePrimaryPassword(password);
    await _client.rpc('mark_employee_initial_password_changed');
  }

  Future<bool> secondaryPasswordConfigured() async {
    if (_client.auth.currentUser == null) return false;
    final value = await _client.rpc('secondary_password_configured');
    return value == true;
  }

  Future<void> setSecondaryPassword(String password) async {
    await _client.rpc(
      'set_secondary_password',
      params: {'p_password': password},
    );
  }

  Future<bool> verifySecondaryPassword(String password) async {
    final value = await _client.rpc(
      'verify_secondary_password',
      params: {'p_password': password},
    );
    return value == true;
  }

  Future<bool> hasCompanyMembership() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    return rows.isNotEmpty;
  }

  Future<void> completeCompanyProfile({
    required String displayName,
    required String companyName,
    String? postalCode,
    String? address,
    String? phone,
    String? fax,
    String? email,
    String? bankName,
    String? bankBranch,
    String? bankAccountType,
    String? bankAccountNumber,
    String? bankAccountHolder,
  }) async {
    await _client.rpc(
      'complete_initial_company_profile',
      params: {
        'p_display_name': displayName.trim(),
        'p_company_name': companyName.trim(),
        'p_postal_code': _nullable(postalCode),
        'p_address': _nullable(address),
        'p_phone': _nullable(phone),
        'p_fax': _nullable(fax),
        'p_email': _nullable(email),
        'p_bank_name': _nullable(bankName),
        'p_bank_branch': _nullable(bankBranch),
        'p_bank_account_type': _nullable(bankAccountType),
        'p_bank_account_number': _nullable(bankAccountNumber),
        'p_bank_account_holder': _nullable(bankAccountHolder),
      },
    );
  }

  bool get companySetupDeferred =>
      _client.auth.currentUser?.userMetadata?['sko_company_setup_deferred'] == true;

  Future<void> setCompanySetupDeferred(bool value) async {
    final current = _client.auth.currentUser;
    final metadata = Map<String, dynamic>.from(current?.userMetadata ?? const {});
    metadata['sko_company_setup_deferred'] = value;
    await _client.auth.updateUser(
      UserAttributes(data: metadata),
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  String? _nullable(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
