import 'app_store_version_repository.dart';
import 'app_version_policy.dart';

typedef AppStoreLookup = Future<AppStoreVersionInfo?> Function({
  required String bundleId,
  required String country,
});

class AppUpdateNoticeData {
  const AppUpdateNoticeData({
    required this.currentVersion,
    required this.latestVersion,
    required this.requirement,
    required this.storeUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final AppUpdateRequirement requirement;
  final Uri storeUrl;

  bool get isRequired => requirement == AppUpdateRequirement.required;
}

class AppUpdateCheckService {
  AppUpdateCheckService({
    AppStoreLookup? lookup,
  }) : _lookup = lookup ?? _defaultLookup;

  final AppStoreLookup _lookup;

  static Future<AppStoreVersionInfo?> _defaultLookup({
    required String bundleId,
    required String country,
  }) async {
    final repository = AppStoreVersionRepository();
    try {
      return await repository.lookup(
        bundleId: bundleId,
        country: country,
      );
    } finally {
      repository.close();
    }
  }

  Future<AppUpdateNoticeData?> check({
    required String currentVersion,
    required String bundleId,
    String country = 'jp',
    String? minimumSupportedVersion,
  }) async {
    final published = await _lookup(
      bundleId: bundleId,
      country: country,
    );
    if (published == null) return null;

    final policy = AppVersionPolicy(
      latestVersion: published.version,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    final requirement = policy.evaluate(currentVersion);
    if (requirement == AppUpdateRequirement.none) return null;

    return AppUpdateNoticeData(
      currentVersion: currentVersion,
      latestVersion: published.version,
      requirement: requirement,
      storeUrl: published.storeUrl,
    );
  }
}
