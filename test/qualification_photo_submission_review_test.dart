import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_photo_submission_review_repository.dart';

void main() {
  test('ordered multi photos are preserved including a retained PDF', () {
    expect(
      QualificationPhotoSubmissionReviewRepository.paths({
        'photo_contract_version': 1,
        'photo_paths': [
          'company/worker/target/front.jpg',
          'company/worker/target/back.pdf',
          'company/worker/target/extra.png',
        ],
      }),
      [
        'company/worker/target/front.jpg',
        'company/worker/target/back.pdf',
        'company/worker/target/extra.png',
      ],
    );
  });
  test('legacy single photo remains available', () {
    expect(
      QualificationPhotoSubmissionReviewRepository.paths({
        'attachment_path': 'old.pdf',
      }),
      ['old.pdf'],
    );
  });
  test('malformed photo sets never fall back to a partial primary photo', () {
    for (final paths in [
      null,
      ['a', 'a'],
      [' '],
      [7],
      List.generate(21, (i) => '$i.jpg'),
    ]) {
      expect(
        () => QualificationPhotoSubmissionReviewRepository.paths({
          'version': 1,
          'photo_paths': paths,
          'attachment_path': 'old.jpg',
        }),
        throwsStateError,
      );
    }
  });
}
