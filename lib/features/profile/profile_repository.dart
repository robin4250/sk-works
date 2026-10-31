import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../shared/trade_document_form_session.dart';

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

/// Read evidence, never an alternative birthday store or Auth owner.
class ProfileBirthdayEvidence extends ChangeNotifier {
  ProfileBirthdayEvidence._({
    required SupabaseClient client,
    required TradeDocumentFormSession lease,
    required Session session,
    required this.workerId,
    required this.companyId,
    required this.supported,
    required this.birthDate,
  }) : _client = client, _lease = lease, _session = session {
    _lease.addListener(_changed);
  }

  final SupabaseClient _client;
  final TradeDocumentFormSession _lease;
  final Session _session;
  final String workerId;
  final String companyId;
  final bool supported;
  final String? birthDate;
  bool _disposed = false;

  bool get canEdit => !_disposed && supported && _lease.isCurrent;
  void _changed() => notifyListeners();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lease.removeListener(_changed);
    _lease.dispose();
    super.dispose();
  }
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

  static DateTime birthdayToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(now.year, now.month, now.day);
  }

  static String? _birthday(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw StateError('生年月日を正しい日付で確認してください。');
    }
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String().substring(0, 10) != value ||
        date.isBefore(DateTime(1900)) || date.isAfter(birthdayToday())) {
      throw StateError('生年月日を正しい日付で確認してください。');
    }
    return value;
  }

  Future<Map<String, dynamic>> _readBirthday({
    required TradeDocumentFormSession lease,
    required Session session,
    required String workerId,
    required String companyId,
  }) async {
    await lease.ready();
    final members = await lease.readOwnMemberships();
    // This profile has no explicit company chooser. Never adopt load()'s first
    // membership as birthday authority when there is more than one company.
    if (members is! List || members.length != 1 || members.single is! Map ||
        (members.single as Map)['company_id'] != companyId) {
      throw StateError('生年月日の対象会社を一意に確認できません。');
    }
    final workers = await _client.from('workers').select('id')
        .eq('company_id', companyId).eq('user_id', session.user.id)
        .eq('status', 'active').limit(2)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .timeout(const Duration(seconds: 30));
    await lease.ready();
    if (workers.length != 1 || workers.single['id'] != workerId) {
      throw StateError('本人の社員情報を確認できません。');
    }
    final raw = await lease.rpc('current_worker_personnel_profile', const {});
    if (raw is! Map || raw['worker_id'] != workerId) {
      throw StateError('本人の生年月日を照合できません。');
    }
    final contract = raw['birth_date_contract_version'];
    if (contract == null) return {'supported': false, 'birth_date': null};
    if (contract is! int || contract != 1 || !raw.containsKey('birth_date')) {
      throw StateError('生年月日の保存形式を確認できません。');
    }
    return {'supported': true, 'birth_date': _birthday(raw['birth_date'])};
  }

  Future<ProfileBirthdayEvidence> loadOwnBirthday({
    required String workerId,
    required String companyId,
  }) async {
    if (workerId.isEmpty || companyId.isEmpty) {
      throw StateError('本人の社員情報を確認できません。');
    }
    final session = _client.auth.currentSession;
    if (session == null) throw StateError('ログイン状態を確認してください。');
    final lease = TradeDocumentFormSession(_client);
    try {
      final raw = await _readBirthday(lease: lease, session: session,
        workerId: workerId, companyId: companyId);
      lease.requireScope();
      return ProfileBirthdayEvidence._(client: _client, lease: lease,
        session: session, workerId: workerId, companyId: companyId,
        supported: raw['supported'] == true, birthDate: raw['birth_date'] as String?);
    } catch (_) {
      lease.dispose();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> savePersonnelProfile({
    required String workerId,
    required Map<String, dynamic> payload,
    ProfileBirthdayEvidence? birthdayEvidence,
  }) async {
    if (payload.containsKey('birth_date')) {
      final evidence = birthdayEvidence;
      if (evidence == null || !identical(evidence._client, _client) ||
          evidence.workerId != workerId || !evidence.canEdit) {
        throw StateError('生年月日を再読み込みしてから変更してください。');
      }
      final date = _birthday(payload['birth_date']);
      try {
        final current = await _readBirthday(lease: evidence._lease,
          session: evidence._session, workerId: workerId,
          companyId: evidence.companyId);
        if (current['supported'] != true || current['birth_date'] != evidence.birthDate) {
          throw StateError('保存済みの生年月日が変わりました。再読み込みして確認してください。');
        }
        evidence._lease.requireScope();
        final raw = await evidence._lease.rpc('save_worker_personnel_profile', {
          'p_worker_id': workerId,
          'p_payload': {...payload, 'birth_date': date},
        });
        if (raw is! Map || !const ['saved', 'unchanged', 'pending'].contains(raw['status']) ||
            raw['requires_approval'] != (raw['status'] == 'pending') ||
            raw['saved_directly'] != (raw['status'] == 'saved') ||
            (raw['status'] == 'pending' &&
                (raw['request_id'] is! String ||
                 !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(raw['request_id'] as String) ||
                 raw['required_approvals'] is! int ||
                 (raw['required_approvals'] as int) < 1 ||
                 (raw['required_approvals'] as int) > 3))) {
          throw StateError('生年月日の保存結果を確認できません。');
        }
        return Map<String, dynamic>.from(raw);
      } finally {
        // A dispatched failure may have committed. Require a new authoritative
        // read, rather than repeating a writer with the old editing evidence.
        evidence.dispose();
      }
    }
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

