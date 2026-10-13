import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/app_version_policy.dart';

void main() {
  test('same or newer app does not require an update', () {
    const policy = AppVersionPolicy(latestVersion: '1.4.0');

    expect(policy.evaluate('1.4.0'), AppUpdateRequirement.none);
    expect(policy.evaluate('1.4.1'), AppUpdateRequirement.none);
  });

  test('older app receives optional update by default', () {
    const policy = AppVersionPolicy(latestVersion: '1.4.0');

    expect(policy.evaluate('1.3.9'), AppUpdateRequirement.optional);
  });

  test('minimum supported version can require an update later', () {
    const policy = AppVersionPolicy(
      latestVersion: '2.0.0',
      minimumSupportedVersion: '1.8.0',
    );

    expect(policy.evaluate('1.9.0'), AppUpdateRequirement.optional);
    expect(policy.evaluate('1.7.9'), AppUpdateRequirement.required);
  });

  test('semantic comparison handles missing patch and build suffix', () {
    expect(AppVersionPolicy.compare('1.2', '1.2.0'), 0);
    expect(AppVersionPolicy.compare('1.2.1+45', '1.2.0'), greaterThan(0));
  });
}
