import 'dart:convert';
import 'dart:io';

class AppStoreVersionInfo {
  const AppStoreVersionInfo({
    required this.version,
    required this.storeUrl,
  });

  final String version;
  final Uri storeUrl;
}

class AppStoreVersionRepository {
  AppStoreVersionRepository({
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 5),
  }) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final Duration timeout;

  static Uri lookupUri({
    required String bundleId,
    String country = 'jp',
  }) {
    return Uri.https(
      'itunes.apple.com',
      '/lookup',
      {
        'bundleId': bundleId,
        'country': country,
        'entity': 'software',
      },
    );
  }

  Future<AppStoreVersionInfo?> lookup({
    required String bundleId,
    String country = 'jp',
  }) async {
    final trimmedBundleId = bundleId.trim();
    if (trimmedBundleId.isEmpty) return null;

    try {
      final request = await _httpClient
          .getUrl(lookupUri(bundleId: trimmedBundleId, country: country))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      return parseResponse(
        body,
        expectedBundleId: trimmedBundleId,
      );
    } catch (_) {
      return null;
    }
  }

  static AppStoreVersionInfo? parseResponse(
    String body, {
    required String expectedBundleId,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;

      for (final raw in results) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        if (item['bundleId']?.toString() != expectedBundleId) continue;

        final version = item['version']?.toString().trim() ?? '';
        final storeUrlRaw = item['trackViewUrl']?.toString().trim() ?? '';
        final storeUrl = Uri.tryParse(storeUrlRaw);

        if (version.isEmpty ||
            storeUrl == null ||
            !storeUrl.hasScheme ||
            storeUrl.host.isEmpty) {
          continue;
        }

        return AppStoreVersionInfo(
          version: version,
          storeUrl: storeUrl,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  void close() {
    _httpClient.close(force: true);
  }
}
