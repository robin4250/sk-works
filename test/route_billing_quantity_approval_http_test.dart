import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approval_repository.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('billing site choices preserve explicit daily rate and exclude other methods', () {
    final request = RouteBillingQuantityRequest({
      'site_options': [
        {'site_id': 'daily', 'unit_price_yen': 25000, 'man_day_method': true},
        {'site_id': 'fixed', 'unit_price_yen': 0, 'man_day_method': false},
        {'site_id': 'unknown', 'unit_price_yen': 25000},
      ],
    });
    expect(request.siteOptions.single['site_id'], 'daily');
    expect(request.siteOptions.single['unit_price_yen'], 25000);
  });
  test(
    'approval explicitly transmits customer request, version, representative site and quantity; rejects malformed outcome',
    () => HttpOverrides.runWithHttpOverrides(() async {
      const actor = '11111111-1111-4111-8111-111111111111';
      final calls = <Map>[];
      var wrongResult = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        Object response;
        if (request.uri.path == '/auth/v1/token') {
          String encode(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value)))
              .replaceAll('=', '');
          response = {
            'access_token':
                '${encode({'alg': 'HS256'})}.${encode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
            'refresh_token': 'fixture',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'fixture@example.test',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        } else if (request.uri.path.endsWith(
          '/decide_route_billing_quantity',
        )) {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          calls.add(body);
          response = {
            'id': wrongResult ? 'different-customer-request' : 'request-A',
            'status': body['p_decision'] == 'approve' ? 'approved' : 'rejected',
          };
        } else {
          request.response.statusCode = 500;
          response = {'message': 'unexpected request'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        await client.auth.signInWithPassword(
          email: 'fixture@example.test',
          password: 'fixture',
        );
        final repository = RouteBillingQuantityApprovalRepository.forTesting(
          client,
        );
        final request = RouteBillingQuantityRequest({
          'id': 'request-A',
          'customer_id': 'customer-A',
          'quantity': 1,
          'status': 'pending',
          'version': 3,
        });
        await expectLater(
          repository.decide(request: request, approve: true, quantity: 0.5),
          throwsStateError,
        );
        expect(calls, isEmpty);
        expect(
          await repository.decide(
            request: request,
            approve: true,
            quantity: 0.5,
            siteId: 'explicit-site',
            unitPriceYen: 25000,
          ),
          'approved',
        );
        expect(calls.single, {
          'p_request_id': 'request-A',
          'p_quantity': 0.5,
          'p_decision': 'approve',
          'p_note': null,
          'p_expected_version': 3,
          'p_representative_site_id': 'explicit-site',
          'p_unit_price_yen': 25000,
        });
        wrongResult = true;
        await expectLater(
          repository.decide(
            request: request,
            approve: true,
            quantity: 1,
            siteId: 'explicit-site',
            unitPriceYen: 25000,
          ),
          throwsStateError,
        );
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    }, _RealHttpOverrides()),
  );
}
