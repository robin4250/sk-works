import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class EmployeeOnboardingRepository {
  EmployeeOnboardingRepository(this._client);

  final SupabaseClient _client;
  static const bucket = 'employee-onboarding-documents';

  static EmployeeOnboardingRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return EmployeeOnboardingRepository(SupabaseBackend.client);
  }

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('SKOへのログインが必要です。');
    return id;
  }

  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  EmployeeOnboardingRequest beginRequest(bool Function() isActive) {
    final session = _client.auth.currentSession;
    if (session == null) throw StateError('SKOへのログインが必要です。');
    return EmployeeOnboardingRequest._(
      session.user.id,
      session.accessToken,
      () => isActive() && currentUserId == session.user.id,
    );
  }

  Future<EmployeeOnboardingPhotoCapability?> loadPhotoCapability({
    required EmployeeOnboardingRequest request,
  }) async {
    request.check();
    try {
      final value = await _client.rpc('employee_onboarding_photo_capability')
          .setHeader('Authorization', request.authorization).retry(enabled: false);
      request.check();
      return EmployeeOnboardingPhotoCapability.parse(value);
    } on PostgrestException catch (error) {
      request.check();
      if (error.code == 'PGRST202') return null;
      rethrow;
    }
  }

  Future<String> uploadImage({
    required String kind,
    required Uint8List bytes,
    required String filename,
    EmployeeOnboardingRequest? request,
  }) async {
    request?.check();
    final safeExt = filename.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final path =
        '${request?.userId ?? _userId}/$kind-${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    final storage = _client.storage.from(bucket);
    if (request != null) storage.setHeader('Authorization', request.authorization);
    await storage.uploadBinary(
          path,
          bytes,
          retryAttempts: request == null ? null : 0,
          fileOptions: FileOptions(
            contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );
    request?.check();
    return path;
  }

  Future<void> removeImage(String? path) async {
    if (path == null || path.isEmpty) return;
    await _client.storage.from(bucket).remove([path]);
  }

  Future<void> submitProfile({
    required String address,
    required String bloodType,
    required String familyComposition,
    required String emergencyRelation,
    required String emergencyName,
    required String emergencyPhone,
    required String emergencyAddress,
    required String portraitPath,
    required String myNumberFrontPath,
    required String myNumberBackPath,
    EmployeeOnboardingRequest? request,
  }) async {
    request?.check();
    final call = _client.rpc(
      'save_employee_onboarding_profile',
      params: {
        'p_address': address.trim(),
        'p_blood_type': bloodType.trim(),
        'p_family_composition': familyComposition.trim(),
        'p_emergency_relation': emergencyRelation.trim(),
        'p_emergency_name': emergencyName.trim(),
        'p_emergency_phone': emergencyPhone.trim(),
        'p_emergency_address': emergencyAddress.trim(),
        'p_portrait_path': portraitPath,
        'p_my_number_front_path': myNumberFrontPath,
        'p_my_number_back_path': myNumberBackPath,
      },
    );
    if (request == null) {
      await call;
    } else {
      await call.setHeader('Authorization', request.authorization).retry(enabled: false);
      request.check();
    }
  }

  // This endpoint asserts server-side retention even if the old save was restored.
  // Missing/error responses MUST NOT fall back to the old NULL-photo endpoint.
  Future<void> submitProfileWithoutPhotos({
    required Map<String, String> fields,
    required EmployeeOnboardingRequest request,
  }) async {
    request.check();
    await _client.rpc('save_employee_onboarding_profile_without_photos',
      params: fields.map((key, value) => MapEntry('p_$key', value.trim())),
    ).setHeader('Authorization', request.authorization).retry(enabled: false);
    request.check();
  }

  Future<bool> canReview() async {
    final value = await _client.rpc('can_review_employee_onboarding');
    return value == true;
  }

  Future<List<Map<String, dynamic>>> loadPendingApprovals() async {
    final value =
        await _client.rpc('pending_employee_onboarding_review_rows');
    if (value is! List) return const [];
    return value
        .map<Map<String, dynamic>>(
          (row) => Map<String, dynamic>.from(row as Map),
        )
        .toList(growable: false);
  }

  Future<void> approve(String inviteId) async {
    await _client.rpc(
      'approve_employee_onboarding',
      params: {'p_invite_id': inviteId},
    );
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(bucket).createSignedUrl(path, 300);
}


class EmployeeOnboardingRequest {
  EmployeeOnboardingRequest._(this.userId, this._token, this._isActive);
  final String userId;
  final String _token;
  final bool Function() _isActive;
  String get authorization => 'Bearer $_token';

  void check() {
    if (!_isActive()) {
      throw StateError('ログイン状態または画面の状態が変わりました。入力内容を確認して再度お試しください。');
    }
  }
}

class EmployeeOnboardingPhotoCapability {
  const EmployeeOnboardingPhotoCapability._(this.hasExistingImages, this.photoUploadAllowed);
  final bool hasExistingImages;
  final bool photoUploadAllowed;

  static EmployeeOnboardingPhotoCapability parse(dynamic value) {
    if (value is! Map || value.length != 2 ||
        value['has_existing_images'] is! bool ||
        value['photo_upload_allowed'] is! bool) {
      throw const FormatException('写真登録の状態を確認できませんでした。');
    }
    return EmployeeOnboardingPhotoCapability._(
      value['has_existing_images'] as bool,
      value['photo_upload_allowed'] as bool,
    );
  }
}
