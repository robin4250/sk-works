import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class EmployeeOnboardingRepository {
  EmployeeOnboardingRepository._(this._client);

  final SupabaseClient _client;
  static const bucket = 'employee-onboarding-documents';

  static EmployeeOnboardingRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    if (SupabaseBackend.client.auth.currentUser == null) return null;
    return EmployeeOnboardingRepository._(SupabaseBackend.client);
  }

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('SKOへのログインが必要です。');
    return id;
  }

  Future<String> uploadImage({
    required String kind,
    required Uint8List bytes,
    required String filename,
  }) async {
    final safeExt = filename.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final path =
        '$_userId/$kind-${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );
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
  }) async {
    await _client.rpc(
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
  }

  Future<bool> canReview() async {
    final value = await _client.rpc('can_review_employee_onboarding');
    return value == true;
  }

  Future<List<Map<String, dynamic>>> loadPendingApprovals() async {
    final value = await _client.rpc('pending_employee_onboarding_rows');
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
