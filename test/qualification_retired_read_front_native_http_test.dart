import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

class _NativeHttp extends HttpOverrides {}

void main() {
  final contextPath = Platform.environment['SKO_RETIRED_QUALIFICATION_HTTP_CONTEXT'];
  test('front history reads preserve inactive records without invoking installed legacy initializer', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final config = jsonDecode(File(contextPath!).readAsStringSync()) as Map;
      if (config['url'] != 'http://127.0.0.1:55443' ||
          config['apikey'] != 'fixture-only' ||
          config['actor'] != '10000000-0000-0000-0000-000000000001' ||
          config['company'] != '20000000-0000-0000-0000-000000000001' ||
          config['worker'] != '30000000-0000-0000-0000-000000000001' ||
          config['token'] is! String ||
          !(config['token'] as String).endsWith('.synthetic')) {
        // Never include rejected key/token values in a test failure.
        throw StateError('isolated loopback fixture context required');
      }
      final headers = <String, String>{
        'apikey': config['apikey'] as String,
        'Authorization': 'Bearer ${config['token']}',
        'content-type': 'application/json',
      };
      Future<Map<String, dynamic>> info() async {
        final response = await http.get(Uri.parse('${config['url']}/fixture-info'), headers: headers)
            .timeout(const Duration(seconds: 10));
        expect(response.statusCode, 200);
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
      final client = SupabaseClient(config['url'] as String, config['apikey'] as String,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(client.dispose);
      await client.auth.setInitialSession(jsonEncode({
        'access_token': config['token'],
        'refresh_token': 'synthetic-qualification-only',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': config['actor'], 'aud': 'authenticated',
          'created_at': '2026-11-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }));
      final cloud = QualificationCloudRepository.forTesting(client);
      final certificates = QualificationCertificateRepository.forTesting(client);
      final before = await info();
      final original = Map<String, dynamic>.from(before['original'] as Map);
      expect(original['worker_status'], 'inactive');
      expect(original['qualification_count'], 3);

      // The exact legacy mutating initializer remains installed, but these reads must never call it.
      final cloudRead = await cloud.loadAll();
      final certificateRead = await certificates.loadAll();
      for (final read in [cloudRead, certificateRead]) {
        final workers = read['workers'] as List;
        final qualifications = read['qualifications'] as List;
        expect(workers, hasLength(1));
        expect(workers.single['id'], config['worker']);
        expect(workers.single['status'], 'inactive');
        expect(qualifications, hasLength(1));
        final saved = qualifications.single as Map;
        expect(saved['id'], config['qualification']);
        expect(saved['worker_id'], config['worker']);
        expect(saved['certificate_number'], 'KEPT-123');
        expect(saved['attachment_path'], '${config['company']}/${config['worker']}/front.jpg');
        expect(saved['attachment_back_path'], '${config['company']}/${config['worker']}/back.jpg');
        expect(saved['attachment_extra_paths'], ['${config['company']}/${config['worker']}/extra.jpg']);
        expect(saved['notes'], 'preserved notes');
      }
      // Actual selected SQL read policy, through the real SDK without worker filters.
      final visible = await client.from('worker_qualifications').select('id,worker_id');
      expect(visible, hasLength(1));
      expect(visible.single['id'], config['qualification']);
      final after = await info();
      expect(after['phase'], 'old');
      final finalRows = after['current'] as Map;
      expect(finalRows['worker_status'], 'inactive');
      expect(finalRows['worker_count'], original['worker_count']);
      expect(finalRows['qualification_hash'], original['qualification_hash']);
      expect(finalRows['own_qualification'], original['own_qualification']);
      expect(after['synthetic_auth'], true);
      expect(after['custom_http_bridge'], true);
      expect(after['real_storage_bytes'], false);
      expect(after['production_catalog'], false);
      final trace = (after['trace'] as List).cast<Map>();
      expect(trace.where((row) => row['name'] == 'ensure_current_user_worker'), isEmpty);
      expect(trace.any((row) => row['name'] == 'current_feature_permissions'), true);
      expect(trace.where((row) => row['kind'] == 'rpc').every((row) =>
          ['ensure_current_user_worker', 'current_feature_permissions'].contains(row['name'])), true);
    }, _NativeHttp());
  }, skip: contextPath == null ? 'dedicated isolated PostgreSQL HTTP context required' : false);
}
