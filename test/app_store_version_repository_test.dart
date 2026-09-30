import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/app_store_version_repository.dart';

void main() {
  test('builds App Store lookup URL for bundle id and country', () {
    final uri = AppStoreVersionRepository.lookupUri(
      bundleId: 'com.robin4250.sko',
      country: 'jp',
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'itunes.apple.com');
    expect(uri.path, '/lookup');
    expect(uri.queryParameters['bundleId'], 'com.robin4250.sko');
    expect(uri.queryParameters['country'], 'jp');
    expect(uri.queryParameters['entity'], 'software');
  });

  test('parses matching published app metadata', () {
    const body = '''
{
  "resultCount": 1,
  "results": [
    {
      "bundleId": "com.robin4250.sko",
      "version": "1.4.2",
      "trackViewUrl": "https://apps.apple.com/jp/app/sko/id123456789"
    }
  ]
}
''';

    final info = AppStoreVersionRepository.parseResponse(
      body,
      expectedBundleId: 'com.robin4250.sko',
    );

    expect(info, isNotNull);
    expect(info!.version, '1.4.2');
    expect(
      info.storeUrl.toString(),
      'https://apps.apple.com/jp/app/sko/id123456789',
    );
  });

  test('returns null before the app is published', () {
    final info = AppStoreVersionRepository.parseResponse(
      '{"resultCount":0,"results":[]}',
      expectedBundleId: 'com.robin4250.sko',
    );

    expect(info, isNull);
  });

  test('ignores metadata for a different bundle id', () {
    const body = '''
{
  "resultCount": 1,
  "results": [
    {
      "bundleId": "com.example.other",
      "version": "9.9.9",
      "trackViewUrl": "https://apps.apple.com/jp/app/other/id999"
    }
  ]
}
''';

    final info = AppStoreVersionRepository.parseResponse(
      body,
      expectedBundleId: 'com.robin4250.sko',
    );

    expect(info, isNull);
  });

  test('rejects malformed version lookup payload', () {
    final info = AppStoreVersionRepository.parseResponse(
      'not-json',
      expectedBundleId: 'com.robin4250.sko',
    );

    expect(info, isNull);
  });
}
