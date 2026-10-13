import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/auth_error_message.dart';

void main() {
  group('friendlyAuthErrorMessage', () {
    test('maps rate limit errors', () {
      expect(
        friendlyAuthErrorMessage('over request rate limit'),
        contains('少し待って'),
      );
    });

    test('maps expired OTP errors', () {
      expect(
        friendlyAuthErrorMessage('OTP has expired'),
        contains('期限切れ'),
      );
    });

    test('maps SMS provider configuration errors', () {
      expect(
        friendlyAuthErrorMessage('SMS provider not configured'),
        contains('SMSプロバイダ'),
      );
    });

    test('maps already registered user errors', () {
      expect(
        friendlyAuthErrorMessage('User already registered'),
        contains('すでに登録'),
      );
    });

    test('preserves unknown messages', () {
      expect(
        friendlyAuthErrorMessage('custom auth failure'),
        'custom auth failure',
      );
    });
  });
}
