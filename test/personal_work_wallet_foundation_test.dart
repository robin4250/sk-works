import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/personal_wallet_ad_policy.dart';
import 'package:sk_works/domain/personal_work_wallet.dart';

void main() {
  test('personal work data survives company disconnect', () {
    for (final key in <String>[
      'profile',
      'sko_personal_id',
      'qualification',
      'qualification_certificate',
      'personal_document',
    ]) {
      expect(PersonalWorkWalletPolicy.survivesEmploymentDisconnect(key), isTrue);
      expect(PersonalWorkWalletPolicy.canShareWithNewCompany(key), isTrue);
    }
  });

  test('company-owned records do not transfer to a new employer', () {
    for (final key in <String>['payroll', 'invoice', 'approval_history']) {
      expect(PersonalWorkWalletPolicy.canShareWithNewCompany(key), isFalse);
    }
  });

  test('ads are personal-free-mode only and never target sensitive work data', () {
    expect(
      PersonalWalletAdPolicy.adsEligible(
        personalFreeMode: true,
        activeCompanyWorkspace: false,
      ),
      isTrue,
    );
    expect(
      PersonalWalletAdPolicy.adsEligible(
        personalFreeMode: false,
        activeCompanyWorkspace: true,
      ),
      isFalse,
    );
    expect(
      PersonalWalletAdPolicy.forbiddenTargetingData,
      contains('qualification'),
    );
    expect(PersonalWalletAdPolicy.forbiddenTargetingData, contains('my_number'));
  });
}
