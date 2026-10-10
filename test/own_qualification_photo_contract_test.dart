import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

void main() {
  test('legacy fallback is limited to absent optional photo columns', () {
    for (final code in ['42703', 'PGRST204']) {
      expect(
        QualificationCloudRepository.isMissingOwnPhotoColumn(
          PostgrestException(
            message: 'column worker_qualifications.attachment_extra_paths does not exist',
            code: code,
          ),
          'attachment_extra_paths',
        ),
        isTrue,
      );
    }
    for (final error in [
      const PostgrestException(
        message: 'permission denied attachment_extra_paths',
        code: '42501',
      ),
      const PostgrestException(
        message: 'column notes does not exist',
        code: '42703',
      ),
      const PostgrestException(
        message: 'attachment_extra_paths_backup missing',
        code: '42703',
      ),
    ]) {
      expect(
        QualificationCloudRepository.isMissingOwnPhotoColumn(
          error,
          'attachment_extra_paths',
        ),
        isFalse,
      );
    }
  });
  test('saved certificate photos preserve front back extra order and skip malformed duplicates', () {
    final photos = QualificationCloudRepository.ownPhotoAttachments({
      'attachment_path': 'front.jpg',
      'attachment_back_path': 'back.jpg',
      'attachment_extra_paths': ['extra.jpg', 'front.jpg', null, 42, ''],
    });
    expect(photos.map((photo) => photo.path), [
      'front.jpg',
      'back.jpg',
      'extra.jpg',
    ]);
    expect(photos.map((photo) => photo.label), ['表面', '裏面', '追加写真 1']);
    expect(
      QualificationCloudRepository.ownPhotoAttachments({
        'attachment_path': 'legacy.jpg',
      }).single.path,
      'legacy.jpg',
    );
    expect(
      QualificationCloudRepository.ownPhotoAttachments({
        'attachment_extra_paths': 'invalid',
      }),
      isEmpty,
    );
  });

  test('own preview uses existing worker scope and never uploads or deletes images', () {
    final repository = File(
      'lib/features/qualifications/qualification_cloud_repository.dart',
    ).readAsStringSync();
    final preview = repository.substring(
      repository.indexOf('Future<String> createOwnQualificationPhotoUrl'),
      repository.indexOf(
        'Future<Map<String, dynamic>> loadOwnQualificationWorkspace',
      ),
    );
    expect(repository, contains(".eq('worker_id', workerId)"));
    expect(repository, contains(".eq('company_id', companyId)"));
    expect(preview, contains('ownPhotoAttachments(rows.single)'));
    expect(preview, contains('currentUserId != actor'));
    expect(preview, contains('createSignedUrl'));
    expect(preview, isNot(contains('upload')));
    expect(preview, isNot(contains('.remove(')));
    final page = File(
      'lib/features/qualifications/own_qualification_registration_page.dart',
    ).readAsStringSync();
    expect(page, contains('本人による資格証写真の追加・差し替えは現在停止中'));
    expect(page, contains('InteractiveViewer'));
  });
}
