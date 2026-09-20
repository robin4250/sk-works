import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';

void main() {
  group('SecureOnboardingRepository.normalizeJapanesePhoneValue', () {
    test('normalizes domestic Japanese mobile number', () {
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '09012345678',
        ),
        '+819012345678',
      );
    });

    test('normalizes hyphenated Japanese mobile number', () {
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '090-1234-5678',
        ),
        '+819012345678',
      );
    });

    test('keeps E.164 Japanese number', () {
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '+81 90 1234 5678',
        ),
        '+819012345678',
      );
    });

    test('normalizes 81-prefixed number without plus', () {
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '819012345678',
        ),
        '+819012345678',
      );
    });

    test('normalizes other Japanese mobile prefixes', () {
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '080-1111-2222',
        ),
        '+818011112222',
      );
      expect(
        SecureOnboardingRepository.normalizeJapanesePhoneValue(
          '070-3333-4444',
        ),
        '+817033334444',
      );
    });
  });
}
