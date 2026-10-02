import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class ProfileData {
  const ProfileData({
    required this.displayName,
    required this.phone,
    required this.email,
    required this.companyName,
    required this.companyId,
    required this.role,
    required this.personalSkoId,
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
  final String? avatarPath;
  final String? avatarUrl;
}

class ProfileRepository {
  ProfileRepository._(this._client);

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

    final memberships = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);

    String companyName = '';
    String companyId = '';
    String role = 'viewer';

    if (memberships.isNotEmpty) {
      companyId = memberships.first['company_id'] as String;
      role = memberships.first['role']?.toString() ?? 'viewer';
      final companies = await _client
          .from('companies')
          .select('name')
          .eq('id', companyId)
          .limit(1);
      if (companies.isNotEmpty) {
        companyName = companies.first['name']?.toString() ?? '';
      }
    }

    final profiles = await _client
        .from('user_profiles')
        .select('display_name, phone, avatar_storage_path')
        .eq('user_id', user.id)
        .limit(1);

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
        (await _client.rpc('ensure_personal_sko_id'))?.toString() ?? '';

    return ProfileData(
      displayName: profile['display_name']?.toString() ??
          user.phone ??
          user.email ??
          'ユーザー',
      phone: profile['phone']?.toString() ?? user.phone ?? '',
      email: user.email ?? '',
      companyName: companyName,
      companyId: companyId,
      role: role,
      personalSkoId: personalSkoId,
      avatarPath: avatarPath,
      avatarUrl: avatarUrl,
    );
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
    if (!value.startsWith('SKO-')) value = 'SKO-' + value;
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
    await _client.auth.updateUser(
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
    await _client.auth.verifyOTP(
      type: OtpType.phoneChange,
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

    final existing = await _client
        .from('user_profiles')
        .select('avatar_storage_path')
        .eq('user_id', user.id)
        .limit(1);
    final oldPath = existing.isEmpty
        ? null
        : existing.first['avatar_storage_path']?.toString();

    final extension = _extension(filename);
    final path =
        '${user.id}/avatar-${DateTime.now().microsecondsSinceEpoch}$extension';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
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

  String _extension(String filename) {
    final index = filename.lastIndexOf('.');
    if (index < 0 || index == filename.length - 1) return '.jpg';
    final ext = filename.substring(index).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext)) return '.jpg';
    return ext;
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
