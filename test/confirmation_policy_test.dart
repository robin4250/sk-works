import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/confirmation_policy.dart';

void main() {
  test('state-changing actions require confirmation', () {
    for (final action in ConfirmedAction.values) {
      expect(ConfirmationPolicy.requiresConfirmation(action), isTrue);
    }
  });

  test('read-only navigation does not need confirmation', () {
    for (final action in <String>['view', 'search', 'filter', 'navigate']) {
      expect(ConfirmationPolicy.isReadOnlyAction(action), isTrue);
    }
  });
}
