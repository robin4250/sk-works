import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_step_up_policy.dart';

void main() {
  test('master access requires role device biometric and second password', () {
    final now = DateTime(2026, 9, 30, 2);
    expect(
      MasterStepUpPolicy.requiresFreshAuthentication(
        isMasterAdmin: true,
        trustedDevice: true,
        biometricVerified: true,
        secondPasswordVerified: true,
        verifiedAt: now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      isFalse,
    );

    expect(
      MasterStepUpPolicy.requiresFreshAuthentication(
        isMasterAdmin: true,
        trustedDevice: true,
        biometricVerified: true,
        secondPasswordVerified: false,
        verifiedAt: now,
        now: now,
      ),
      isTrue,
    );
  });

  test('master step-up expires and clears on app exit', () {
    final now = DateTime(2026, 9, 30, 2);
    expect(
      MasterStepUpPolicy.requiresFreshAuthentication(
        isMasterAdmin: true,
        trustedDevice: true,
        biometricVerified: true,
        secondPasswordVerified: true,
        verifiedAt: now.subtract(const Duration(minutes: 15)),
        now: now,
      ),
      isTrue,
    );
    expect(MasterStepUpPolicy.shouldClearOnAppExit(), isTrue);
  });
}
