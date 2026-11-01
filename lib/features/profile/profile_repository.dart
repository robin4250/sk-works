import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'avatar_upload_format.dart';

class ProfileData {
  const ProfileData({
    required this.displayName,
    required this.phone,
    required this.email,
    required this.companyName,
    required this.companyId,
    required this.role,
    required this.personalSkoId,
    this.companyAvailable = true,
    this.avatarPath,
    this.avatarUrl,
  });

  final String displayName;
  final String phone;
  final String email;
  final String companyName;
  final String companyId;
  final String role;
  final String personalSkoId;
  final bool companyAvailable;
  final String? avatarPath;
  final String? avatarUrl;
}

class ProfileRepository {
  ProfileRepository._(this._client);

  ProfileRepository.forClient(this._client);

  final SupabaseClient _client;
  static const _bucket = 'profile-photos';

  static ProfileRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return ProfileRepository._(client);
  }

  Future<ProfileData> load() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final session = _client.auth.currentSession;
    if (session == null) throw StateError('ログインが必要です。');
    final owner = AppAuthMutationGateway.forClient(_client);
    final epoch = await owner.externalFlowAdmission();
    final guard = SecondaryResetSessionGuard(currentSession: () => _client.auth.currentSession,
      changes: _client.auth.onAuthStateChange);
    Future<void> check() async {
      if (epoch == null || !owner.isExternalFlowCurrent(epoch) ||
          SecondaryResetSessionGuard.identityOf(session) != SecondaryResetSessionGuard.identityOf(_client.auth.currentSession)) {
        throw StateError('ログイン状態が変わりました。画面を開き直してください。');
      }
      await guard.checkAfterQueuedEvents();
    }
    try {
    await check();
    String companyName = '', companyId = '', role = 'viewer';
    var companyAvailable = true;
    try {
      final memberships = await _client.from('company_members').select('company_id, role')
          .eq('user_id', user.id).limit(1)
          .setHeader('Authorization', 'Bearer ${session.accessToken}');
      await check();
      if (memberships.isNotEmpty) {
        companyId = memberships.first['company_id'] as String;
        role = memberships.first['role']?.toString() ?? 'viewer';
        final companies = await _client.from('companies').select('name').eq('id', companyId).limit(1)
            .setHeader('Authorization', 'Bearer ${session.accessToken}');
        await check();
        if (companies.isNotEmpty) companyName = companies.first['name']?.toString() ?? '';
      }
    } catch (_) {
      // Company availability never determines the existence of personal data.
      await check();
      companyAvailable = false; companyName = ''; companyId = ''; role = 'viewer';
    }

    final profiles = await _client
        .from('user_profiles')
        .select('display_name, phone, avatar_storage_path')
        .eq('user_id', user.id)
        .limit(1).setHeader('Authorization', 'Bearer ${session.accessToken}');
    await check();

    final profile = profiles.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(profiles.first);
    final avatarPath = profile['avatar_storage_path']?.toString();

    String? avatarUrl;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      try {
        avatarUrl =
            await _client.storage.from(_bucket).createSignedUrl(avatarPath, 3600);
      } catch (_) {
        avatarUrl = null;
      }
    }

    final personalSkoId =
        (await _client.rpc('ensure_personal_sko_id').setHeader('Authorization', 'Bearer ${session.accessToken}'))?.toString() ?? '';
    await check();

    return ProfileData(
      displayName: profile['display_name']?.toString() ??
          user.phone ??
          user.email ??
          'ユーザー',
      phone: profile['phone']?.toString() ?? user.phone ?? '',
      email: user.email ?? '',
      companyAvailable: companyAvailable,
      companyName: companyName,
      companyId: companyId,
      role: role,
      personalSkoId: personalSkoId,
      avatarPath: avatarPath,
      avatarUrl: avatarUrl,
    );
    } finally { await guard.close(); }
  }

  Future<Map<String, dynamic>?> loadPersonnelProfile() async {
    final raw = await _client.rpc('current_worker_personnel_profile');
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> savePersonnelProfile({
    required String workerId,
    required Map<String, dynamic> payload,
  }) async {
    final raw = await _client.rpc(
      'save_worker_personnel_profile',
      params: {
        'p_worker_id': workerId,
        'p_payload': payload,
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  String? get currentAuthPhone => _client.auth.currentUser?.phone;

  Future<String> changePersonalSkoId(String raw) async {
    var value = raw.trim().toUpperCase();
    if (!value.startsWith('SKO-')) value = 'SKO-$value';
    final suffix = value.length >= 4 ? value.substring(4) : '';
    final invalidCharacter = RegExp(r'[^A-Z0-9]').hasMatch(suffix);
    if (suffix.length < 4 || suffix.length > 20 || invalidCharacter) {
      throw StateError('SKO IDはSKO-に続けて英数字4〜20文字で入力してください。');
    }
    final result = await _client.rpc(
      'change_personal_sko_id',
      params: {'p_sko_id': value},
    );
    final id = result?.toString() ?? '';
    if (id.isEmpty) throw StateError('SKO IDを変更できませんでした。');
    return id;
  }
  Future<String> requestPhoneChange(String rawPhone) async {
    final normalized = _normalizeJapanesePhone(rawPhone);
    await AppAuthMutationGateway.forClient(_client).updateUser(
      UserAttributes(phone: normalized),
    );
    return normalized;
  }

  Future<void> resendPhoneChange(String phone) async {
    await _client.auth.resend(
      type: OtpType.phoneChange,
      phone: _normalizeJapanesePhone(phone),
    );
  }

  Future<void> verifyPhoneChange({
    required String phone,
    required String code,
  }) async {
    await AppAuthMutationGateway.forClient(_client).verifyPhoneChange(
      phone: _normalizeJapanesePhone(phone),
      token: code.trim(),
    );
  }

  Future<void> save({
    required String displayName,
    required String phone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    await _client.from('user_profiles').upsert({
      'user_id': user.id,
      'display_name': displayName.trim(),
      'phone': _nullable(phone),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    try {
      await _client.rpc('ensure_current_user_worker');
    } catch (_) {
      // Worker linking can be retried later if company setup is incomplete.
    }
  }

  Future<void> uploadAvatar({
    required Uint8List bytes,
    required String filename,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');

    final format = AvatarUploadFormat.inspect(bytes);

    final existing = await _client
        .from('user_profiles')
        .select('avatar_storage_path')
        .eq('user_id', user.id)
        .limit(1);
    final oldPath = existing.isEmpty
        ? null
        : existing.first['avatar_storage_path']?.toString();

    final extension = format.extension;
    final path =
        '${user.id}/avatar-${DateTime.now().microsecondsSinceEpoch}$extension';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: format.mime),
        );

    try {
      await _client.from('user_profiles').upsert({
        'user_id': user.id,
        'avatar_storage_path': path,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (oldPath != null && oldPath.isNotEmpty && oldPath != path) {
        try {
          await _client.storage.from(_bucket).remove([oldPath]);
        } catch (_) {
          // The new avatar is already active; stale-file cleanup is best effort.
        }
      }
    } catch (_) {
      try {
        await _client.storage.from(_bucket).remove([path]);
      } catch (_) {
        // Preserve the original profile update failure.
      }
      rethrow;
    }
  }

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

  static String domesticJapanesePhoneValue(String raw) {
    final normalized = normalizeJapanesePhoneValue(raw);
    if (normalized.startsWith('+81') && normalized.length > 3) {
      return '0${normalized.substring(3)}';
    }
    return raw.trim();
  }

  static bool isSupportedJapaneseMobileValue(String raw) {
    final normalized = normalizeJapanesePhoneValue(raw);
    return normalized.length == 13 &&
        RegExp(r'^\+81(?:70|80|90)\d{8}').hasMatch(normalized);
  }

  String _normalizeJapanesePhone(String raw) =>
      normalizeJapanesePhoneValue(raw);

  Object? _nullable(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
