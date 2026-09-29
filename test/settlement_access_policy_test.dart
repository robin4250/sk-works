import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/settlement_access_policy.dart';

void main() {
  test('owner and admin require second factor', () {
    expect(
      SettlementAccessPolicy.canAccess(
        role: 'admin',
        delegatedSettlementPermission: false,
        secondFactorVerified: false,
      ),
      isFalse,
    );
    expect(
      SettlementAccessPolicy.canAccess(
        role: 'admin',
        delegatedSettlementPermission: false,
        secondFactorVerified: true,
      ),
      isTrue,
    );
  });

  test('sub-admin requires explicit settlement permission and second factor', () {
    expect(
      SettlementAccessPolicy.canAccess(
        role: 'sub_admin',
        delegatedSettlementPermission: false,
        secondFactorVerified: true,
      ),
      isFalse,
    );
    expect(
      SettlementAccessPolicy.canAccess(
        role: 'sub_admin',
        delegatedSettlementPermission: true,
        secondFactorVerified: true,
      ),
      isTrue,
    );
  });

  test('ordinary employees never see settlement entry', () {
    expect(
      SettlementAccessPolicy.shouldShowEntry(
        role: 'member',
        delegatedSettlementPermission: true,
      ),
      isFalse,
    );
  });
}
