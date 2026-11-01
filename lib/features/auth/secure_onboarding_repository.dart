import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'app_auth_mutation_gateway.dart';
import '../../international/countries/jp/japan_phone_rules.dart';

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

  SecureOnboardingRepository.forClient(this._client);

  final SupabaseClient _client;
  AppAuthMutationGateway get _auth => AppAuthMutationGateway.forClient(_client);

  static SecureOnboardingRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    return SecureOnboardingRepository._(SupabaseBackend.client);
  }

  User? get currentUser => _client.auth.currentUser;

  static String normalizeJapanesePhoneValue(String raw) =>
      JapanPhoneRules.normalize(raw);

  static bool isSupportedJapaneseMobileValue(String raw) =>
      JapanPhoneRules.isSupportedMobile(raw);

  String normalizeJapanesePhone(String raw) =>
      normalizeJapanesePhoneValue(raw);

  Future<bool> registerAdmin({
    required String phone,
    required String password,
    String? captchaToken,
  }) async {
    final normalized = normalizeJapanesePhone(phone);
    final established = await _auth.signUp(
      phone: normalized,
      password: password,
      captchaToken: captchaToken,
      data: const {
        'sko_registration_type': 'admin',
      },
    );
    return established;
  }

  Future<void> resendSmsCode({required String phone, String? captchaToken}) async {
    await _client.auth.resend(
      type: OtpType.sms,
      phone: normalizeJapanesePhone(phone),
      captchaToken: captchaToken,
    );
  }

  Future<void> verifySmsCode({
    required String phone,
    required String code,
    String? captchaToken,
  }) async {
    await _auth.verifySmsCode(
      phone: normalizeJapanesePhone(phone),
      token: code.trim(),
      captchaToken: captchaToken,
    );
  }

  /// Existing email/password accounts only: never creates or links an identity.
  Future<void> signInWithEmail({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final normalized = email.trim();
    if (!isSupportedEmailValue(normalized)) {
      throw ArgumentError('invalid email');
    }
    await _auth.signInWithPassword(
      email: normalized,
      password: password,
      captchaToken: captchaToken,
    );
  }

  static bool isSupportedEmailValue(String raw) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(raw.trim());

  Future<void> signInWithPhone({
    required String phone,
    required String password,
    String? captchaToken,
  }) async {
    await _auth.signInWithPassword(
      phone: normalizeJapanesePhone(phone),
      password: password,
      captchaToken: captchaToken,
    );
  }

  Future<void> updatePrimaryPassword(String password) async {
    if (password.length < 8) {
      throw StateError('password must be at least 8 characters');
    }
    await _auth.updateUser(
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
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null) throw StateError('authentication required');
    var revoked = false;
    final subscription = _client.auth.onAuthStateChange.listen((state) {
      if (state.session?.accessToken != accessToken) revoked = true;
    }, onError: (Object error) {
      revoked = true;
    });
    try {
      final state = await _client
          .rpc('employee_onboarding_state')
          .setHeader('Authorization', 'Bearer $accessToken');
      if (revoked || _client.auth.currentSession?.accessToken != accessToken ||
          state is! Map ||
          state['invite_id'] is! String ||
          (state['invite_id'] as String).isEmpty ||
          !const {
            'invited',
            'password_changed',
            'profile_pending',
          }.contains(state['status'])) {
        throw StateError('有効な初回登録がありません。管理者に確認してください。');
      }
      if (state['status'] == 'invited') {
        final expiresAt = DateTime.tryParse(
          state['expires_at']?.toString() ?? '',
        );
        if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
          throw StateError('初回登録の期限が切れています。管理者に再発行を依頼してください。');
        }
      }
      // This check reduces stale-screen updates; Auth and the marker remain
      // separate operations. It is not an atomic server-side expiry guarantee.
      await updatePrimaryPassword(password);
      if (revoked || _client.auth.currentSession?.accessToken != accessToken) {
        throw StateError('ログイン状態が変わりました。初回登録を開き直してください。');
      }
      await _client
          .rpc('mark_employee_initial_password_changed')
          .setHeader('Authorization', 'Bearer $accessToken');
      if (revoked || _client.auth.currentSession?.accessToken != accessToken) {
        throw StateError('ログイン状態が変わりました。初回登録を開き直してください。');
      }
    } finally {
      await subscription.cancel();
    }
  }

  Future<bool> secondaryPasswordConfigured({String? accessToken}) async {
    if (_client.auth.currentUser == null) return false;
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    final request = _client.rpc('secondary_password_configured');
    final value = await (accessToken == null ? request : request.setHeader('Authorization', 'Bearer $accessToken'));
    return value == true;
  }

  Future<void> setSecondaryPassword(String password, {String? accessToken}) async {
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    final request = _client.rpc('set_secondary_password',
      params: {'p_password': password});
    await (accessToken == null ? request :
      request.setHeader('Authorization', 'Bearer $accessToken'));
  }

  Future<bool> verifySecondaryPassword(String password, {String? accessToken}) async {
    if (accessToken != null && accessToken.isEmpty) throw StateError('Missing captured session');
    final request = _client.rpc(
      'verify_secondary_password',
      params: {'p_password': password},
    );
    final value = await (accessToken == null ? request : request.setHeader('Authorization', 'Bearer $accessToken'));
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
    await _auth.updateUser(
      UserAttributes(data: metadata),
    );
  }

  Future<void> signOut() => _auth.signOut();

  String? _nullable(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}


