import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/app_store_version_repository.dart';
import 'package:sk_works/features/settings/app_update_check_service.dart';
import 'package:sk_works/features/settings/app_version_policy.dart';

void main() {
  AppStoreLookup published(String version) {
    return ({
      required String bundleId,
      required String country,
    }) async {
      return AppStoreVersionInfo(
        version: version,
        storeUrl: Uri.parse('https://apps.apple.com/jp/app/sko/id123'),
      );
    };
  }

  test('returns no notice when current app is latest', () async {
    final service = AppUpdateCheckService(lookup: published('1.4.0'));

    final notice = await service.check(
      currentVersion: '1.4.0',
      bundleId: 'com.robin4250.sko',
    );

    expect(notice, isNull);
  });

  test('returns optional update for older app by default', () async {
    final service = AppUpdateCheckService(lookup: published('1.4.0'));

    final notice = await service.check(
      currentVersion: '1.3.0',
      bundleId: 'com.robin4250.sko',
    );

    expect(notice, isNotNull);
    expect(notice!.requirement, AppUpdateRequirement.optional);
    expect(notice.latestVersion, '1.4.0');
  });

  test('minimum supported version can require update', () async {
    final service = AppUpdateCheckService(lookup: published('2.0.0'));

    final notice = await service.check(
      currentVersion: '1.7.0',
      bundleId: 'com.robin4250.sko',
      minimumSupportedVersion: '1.8.0',
    );

    expect(notice, isNotNull);
    expect(notice!.requirement, AppUpdateRequirement.required);
    expect(notice.isRequired, isTrue);
  });

  test('fails open when App Store metadata is unavailable', () async {
    final service = AppUpdateCheckService(
      lookup: ({
        required String bundleId,
        required String country,
      }) async =>
          null,
    );

    final notice = await service.check(
      currentVersion: '1.0.0',
      bundleId: 'com.robin4250.sko',
    );

    expect(notice, isNull);
  });
}
