import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

void main() {
  test('legacy certificates have no extra photos', () {
    expect(
      QualificationCertificateRepository.extraPaths({
        'attachment_path': 'front.jpg',
        'attachment_back_path': 'back.jpg',
      }),
      isEmpty,
    );
  });
  test('extra photos keep order and exclude invalid entries', () {
    expect(
      QualificationCertificateRepository.extraPaths({
        'attachment_extra_paths': ['third.jpg', '', null, 1, 'fourth.jpg'],
      }),
      ['third.jpg', 'fourth.jpg'],
    );
  });
}
