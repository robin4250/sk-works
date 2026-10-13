import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/profile/profile_repository.dart';

void main() {
  group('ProfileRepository phone ID helpers', () {
    test('normalizes Japanese mobile numbers to E.164', () {
      expect(
        ProfileRepository.normalizeJapanesePhoneValue('090-1234-5678'),
        '+819012345678',
      );
      expect(
        ProfileRepository.normalizeJapanesePhoneValue('+81 80 1111 2222'),
        '+818011112222',
      );
    });

    test('accepts only 070 080 090 mobile IDs', () {
      expect(
        ProfileRepository.isSupportedJapaneseMobileValue('070-1234-5678'),
        isTrue,
      );
      expect(
        ProfileRepository.isSupportedJapaneseMobileValue('03-1234-5678'),
        isFalse,
      );
      expect(
        ProfileRepository.isSupportedJapaneseMobileValue('0901234'),
        isFalse,
      );
    });
  });
}
