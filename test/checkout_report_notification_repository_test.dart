import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/notifications/checkout_report_notification_repository.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notification_target_policy.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/source_notification_target.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/notifications/checkout_report_notification_page.dart';

import 'fixtures/checkout_report_notification_fixture.dart';

CheckoutReportNotificationSnapshot parse(Object? raw) => CheckoutReportNotificationSnapshot.parse(
  raw, actorId: notificationActor, reportId: notificationReport);
String session(String sid) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({'sub':notificationActor,
    'session_id':sid,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token':'synthetic','token_type':'bearer','expires_in':3600,
    'user':{'id':notificationActor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
      'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}});
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dedicated action requires exact UUID and read state does not complete the task', () {
    expect(notificationTargetIsValid(checkoutReportRegistrationAction, notificationReport), true);
    expect(notificationTargetIsValid(checkoutReportRegistrationAction, null), false);
    expect(notificationTargetIsValid(checkoutReportRegistrationAction, 'other'), false);
    final row = AppNotificationRecord(id: 'notification', kind: 'reminder', title: '日報', body: '',
      createdAt: DateTime(2026,10,25), read: true,
      actionKey: checkoutReportRegistrationAction, actionId: notificationReport);
    expect(row.hasBusinessTarget, true);
    expect(SourceNotificationTarget.supports(checkoutReportRegistrationAction), false);
    final destination = notificationDestination(row);
    expect(destination, isA<CheckoutReportNotificationPage>());
    expect((destination as CheckoutReportNotificationPage).reportId, notificationReport);
    expect(row.businessStatus.state.name, 'unknown');
  });
  for (final state in ['report_missing','source_conflict','report_input_incomplete',
    'reporter_signature_missing','reporter_saved_waiting_supervisor','signed_projection_unverified']) {
    test('exact registration state $state is kept separately from task resolution', () {
      final result = parse(registrationNotification(state: state));
      expect(result.resolved, false); expect(result.items.single.state, state);
      expect(result.items.single.reportId, notificationReport);
    });
  }
  test('resolved and disabled are separate and never imply payroll completion', () {
    expect(parse(registrationNotification(resolved: true)).resolved, true);
    final disabled = parse(registrationNotification(enabled: false));
    expect(disabled.enabled, false); expect(disabled.resolved, false);
  });
  test('other actor/report/source and malformed current envelopes fail closed', () {
    final base = registrationNotification();
    final mutations = <Map<String, dynamic>>[
      {...base, 'actor_id': notificationCompany}, {...base, 'report_id': notificationSite},
      {...base, 'resolved': true}, {...base, 'schema': 2}, {...base, 'items': []},
      {...base, 'effective_from': '2026-02-31'}, {...base, 'permission': true},
    ];
    for (final mutation in mutations) {
      expect(() => parse(mutation), throwsA(isA<CheckoutReportNotificationUnavailable>()));
    }
    for (final change in <Map<String, dynamic>>[
      {'report_id': notificationSite}, {'site_id': null},
      {'route_assignment_id': notificationSite}, {'clock_out_id': notificationClockIn},
      {'blocking': false}, {'scope_fingerprint': 'authority'}, {'registration_state':'completed'},
    ]) {
      final row = {...Map<String, dynamic>.from((base['items'] as List).single as Map), ...change};
      expect(() => parse({...base, 'items':[row]}), throwsA(isA<CheckoutReportNotificationUnavailable>()));
    }
  });
  test('reader sends only exact report UUID with captured bearer and no fallback write', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://report-notification.invalid','synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken:false), httpClient:MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(registrationNotification()),200,
          headers:{'content-type':'application/json'},request:request);
      }));
    addTearDown(client.dispose); await client.auth.setInitialSession(session('session-a'));
    final token = client.auth.currentSession!.accessToken;
    final result = await CheckoutReportNotificationRepository(client).load(notificationReport);
    expect(result.items.single.companyId, notificationCompany);
    expect(requests, hasLength(1)); expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/rest/v1/rpc/read_checkout_report_registration_notification');
    expect(jsonDecode(requests.single.body), {'p_report_id':notificationReport});
    expect(requests.single.headers['Authorization'], 'Bearer $token');
    expect(client.auth.currentSession!.accessToken, token);
  });
  test('default async same-actor session ABA cannot return the old RPC response', () async {
    final reached = Completer<void>(), response = Completer<http.Response>();
    final client = SupabaseClient('https://report-notification.invalid','synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken:false), httpClient:MockClient((request) async {
        reached.complete(); return response.future;
      }));
    addTearDown(client.dispose); final original = session('session-a');
    await client.auth.setInitialSession(original);
    final result = CheckoutReportNotificationRepository(client).load(notificationReport);
    final rejected = expectLater(result, throwsA(isA<CheckoutReportNotificationUnavailable>()));
    await reached.future;
    await client.auth.setInitialSession(session('session-b'));
    await client.auth.setInitialSession(original);
    await Future<void>.delayed(Duration.zero);
    response.complete(http.Response(jsonEncode(registrationNotification()),200,
      headers:{'content-type':'application/json'}));
    await rejected;
  });
  test('missing or denied reader stays unavailable, never routes by unscoped table fallback', () async {
    for (final status in [403,404]) {
      var calls = 0;
      final client = SupabaseClient('https://report-notification.invalid','synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
          calls++;return http.Response('{"message":"PRIVATE_REPLY"}',status,
            headers:{'content-type':'application/json'},request:request);
        }));
      await client.auth.setInitialSession(session('session-a'));
      await expectLater(CheckoutReportNotificationRepository(client).load(notificationReport),
        throwsA(isA<CheckoutReportNotificationUnavailable>()));
      expect(calls,1); await client.dispose();
    }
  });
  test('actual notification enrichment keeps read pending and trusts only reader resolution', () async {
    var resolved = false;
    final calls = <String>[];
    final client = SupabaseClient('https://report-notification.invalid','synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken:false), httpClient:MockClient((request) async {
        calls.add(request.url.path);
        final Object? body;
        if (request.url.path.endsWith('/app_notifications')) {
          body = [{'id':notificationClockOut,'kind':'reminder','title':'日報','body':'',
            'action_key':checkoutReportRegistrationAction,'action_id':notificationReport,
            'created_at':'2026-10-25T00:00:00Z','read_at':'2026-10-25T00:01:00Z'}];
        } else if (request.url.path.endsWith('/read_checkout_report_registration_notification')) {
          body = registrationNotification(resolved: resolved);
        } else if (request.url.path.endsWith('/enqueue_due_invoice_approval_notifications')) {
          body = null;
        } else { throw StateError('Unexpected fixture route'); }
        return http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'},request:request);
      }));
    addTearDown(client.dispose);await client.auth.setInitialSession(session('session-a'));
    final repository = AppNotificationRepository.forTesting(client);
    final pending = (await repository.load()).single;
    expect(pending.read,true);expect(pending.businessStatus.state.name,'pending');
    expect(mapAttentionNotification(pending).needsAction,true);
    resolved = true;
    final complete = (await repository.load()).single;
    expect(complete.businessStatus.state.name,'completed');
    expect(mapAttentionNotification(complete).needsAction,false);
    expect(calls.where((p)=>p.endsWith('/read_checkout_report_registration_notification')).length,2);
    expect(calls.any((p)=>p.contains('/get_source_notification_target')),false);
  });

}
