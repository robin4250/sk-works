class OwnQualificationPhotoCapability {
  const OwnQualificationPhotoCapability({
    required this.available,
    required this.uploadAllowed,
    required this.maxPhotos,
  });
  static const unavailable = OwnQualificationPhotoCapability(
    available: false,
    uploadAllowed: false,
    maxPhotos: 0,
  );
  final bool available;
  final bool uploadAllowed;
  final int maxPhotos;
  factory OwnQualificationPhotoCapability.parse(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['photo_submission_available'] is! bool ||
        value['photo_upload_allowed'] is! bool ||
        value['max_photos'] is! int ||
        value['max_photos'] < 1 ||
        value['max_photos'] > 20) {
      return unavailable;
    }
    final available = value['photo_submission_available'] == true;
    return OwnQualificationPhotoCapability(
      available: available,
      uploadAllowed: available && value['photo_upload_allowed'] == true,
      maxPhotos: value['max_photos'] as int,
    );
  }
}

class OwnQualificationPreparedPhotos {
  const OwnQualificationPreparedPhotos({
    required this.id,
    required this.targetId,
    required this.paths,
    required this.uploads,
    required this.status,
    this.cancelled = false,
  });
  final String id;
  final String targetId;
  final List<String> paths;
  final Map<int, ({String path, String extension})> uploads;
  final String status;
  final bool cancelled;

  static OwnQualificationPreparedPhotos parse(
    Object? raw, {
    required String requestId,
    required String targetId,
    required String userId,
    required String companyId,
    required String workerId,
    required List<Map<String, dynamic>> slots,
  }) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['id'] != requestId ||
        raw['target_id'] != targetId ||
        raw['requested_by'] != userId ||
        raw['photo_paths'] is! List ||
        raw['upload_paths'] is! List) {
      throw StateError('写真申請の保存対象を確認できません。');
    }
    final paths = List<String>.from(raw['photo_paths'] as List);
    if (paths.length != slots.length ||
        paths.toSet().length != paths.length ||
        paths.any((path) => path.trim().isEmpty)) {
      throw StateError('写真申請の並び順を確認できません。');
    }
    final uploads = <int, ({String path, String extension})>{};
    for (final entry in raw['upload_paths'] as List) {
      if (entry is! Map ||
          entry['index'] is! int ||
          entry['path'] is! String ||
          entry['extension'] is! String) {
        throw StateError('写真の送信先を確認できません。');
      }
      final index = entry['index'] as int;
      final extension = entry['extension'] as String;
      if (index < 0 ||
          index >= slots.length ||
          uploads.containsKey(index) ||
          slots[index]['extension'] != extension ||
          !const ['jpg', 'jpeg', 'png', 'heic', 'heif'].contains(extension)) {
        throw StateError('写真の送信先が選択内容と一致しません。');
      }
      final expected =
          '$companyId/$workerId/$targetId/submissions/$requestId-${index + 1}.$extension';
      if (entry['path'] != expected || paths[index] != expected) {
        throw StateError('写真の送信先が本人の資格と一致しません。');
      }
      uploads[index] = (path: expected, extension: extension);
    }
    for (var index = 0; index < slots.length; index++) {
      final retained = slots[index]['existing_path'];
      if (retained != null) {
        if (retained != paths[index] || uploads.containsKey(index)) {
          throw StateError('保存済み写真が変更されました。');
        }
      } else if (!uploads.containsKey(index)) {
        throw StateError('追加写真の送信先がありません。');
      }
    }
    if (raw['cancelled'] != null && raw['cancelled'] is! bool) {
      throw StateError('写真申請の取消状態を確認できません。');
    }
    final cancelled = raw['cancelled'] == true;
    final status = raw['status']?.toString() ?? 'draft';
    if (!const ['draft', 'pending', 'approved', 'rejected'].contains(status) ||
        (cancelled && status != 'rejected')) {
      throw StateError('写真申請の状態を確認できません。');
    }
    return OwnQualificationPreparedPhotos(
      id: requestId,
      targetId: targetId,
      paths: List.unmodifiable(paths),
      uploads: Map.unmodifiable(uploads),
      status: status,
      cancelled: cancelled,
    );
  }
}
