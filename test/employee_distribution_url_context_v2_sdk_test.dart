import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/employee_distribution_url_repository.dart';
import 'package:sk_works/features/people/employee_invite_repository.dart';
import 'employee_invite_context_sdk_test.dart' as fixture;

const join = 'https://testflight.apple.com/join/AbC123xy';
const stamp = '2026-11-01T00:00:00+00:00';

class UrlFixture {
  UrlFixture() {
    client = SupabaseClient('https://url-context-fixture.invalid', 'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object? body;
        if (request.url.path == '/auth/v1/token') {
          body = {'access_token': fixture.token(session), 'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer', 'expires_in': 3600,
            'user': {'id': fixture.actor, 'aud': 'authenticated',
              'created_at': stamp, 'app_metadata': {}, 'user_metadata': {}}};
        } else if (request.url.path == '/rest/v1/company_members') {
          body = [{'company_id': fixture.company, 'role': 'owner'}];
        } else if (request.url.path == '/rest/v1/rpc/employee_distribution_url_context_v2') {
          final p = jsonDecode(request.body) as Map<String, dynamic>;
          final command = p['p_command'];
          final envelope = {'version': 2, 'actor_id': fixture.actor,
            'company_id': wrongCompany ? fixture.worker : fixture.company,
            'session_id': session, 'command': command};
          if (command == 'read') {
            body = {...envelope, 'can_save': enabled, 'url': before, 'updated_at': stamp};
          } else if (command == 'save') {
            saves++;
            final payload = p['p_payload'] as Map;
            capturedBefore = payload['before_url'];
            final values = [payload['before_url'] as String?, payload['before_updated_at'] as String?, payload['url'] as String?];
            final fingerprint = sha256.convert(utf8.encode(values.map((v) => v == null ? '-:' : '${utf8.encode(v).length}:$v').join())).toString();
            receipt = {'state': 'committed', 'operation_id': p['p_operation'],
              'original_session_id': session, 'fingerprint': fingerprint,
              'result': conflict ? {'status': 'conflict'} : {'status': 'saved', 'url': join, 'updated_at': stamp}};
            if (barrier != null) await barrier!.future;
            if (loseAck) throw http.ClientException('synthetic ACK lost');
            body = {...envelope, ...receipt!};
          } else {
            body = {...envelope, ...(unobserved ? {'state': 'unobserved', 'operation_id': p['p_operation']} : receipt!)};
          }
        } else {
          throw StateError('Unexpected legacy or external request ${request.url.path}');
        }
        return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }));
    invites = EmployeeInviteRepository.forTesting(client, authEvents: events.stream);
    urls = EmployeeDistributionUrlRepository(client);
  }
  late final SupabaseClient client;
  late final EmployeeInviteRepository invites;
  late EmployeeDistributionUrlRepository urls;
  final events = StreamController<AuthState>.broadcast(sync: true);
  final requests = <http.Request>[];
  String session = fixture.sid;
  String? before;
  Object? capturedBefore;
  bool enabled = true, wrongCompany = false, loseAck = false, unobserved = false, conflict = false;
  int saves = 0;
  Completer<void>? barrier;
  Map<String, dynamic>? receipt;
  Future<void> login() async { await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic'); }
  Future<EmployeeInviteRequest> open() async {
    final request = await invites.beginRequest(companyId: fixture.company);
    await urls.initialize(request);
    return request;
  }
  Future<void> close() async {
    await invites.dispose();
    if (!events.isClosed) await events.close();
    await client.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final before in <String?>[null, '', 'https://legacy.invalid/unknown?value=1']) {
    test('actual SDK preserves raw before-value $before and clears only committed journal', () async {
      final f = UrlFixture()..before = before;
      addTearDown(f.close);
      await f.login(); final request = await f.open();
      final snapshot = await f.urls.read(request);
      expect(snapshot.url, before);
      expect(await f.urls.save(request, snapshot, join), 'saved');
      expect(f.capturedBefore, before);
      expect(f.urls.hasUnknownResult, false);
      expect(f.saves, 1);
      expect(f.requests.where((r) => r.url.path.contains('initial_registration_distribution')), isEmpty);
    });
  }
  test('OFF read stays available but no save or legacy fallback is dispatched', () async {
    final f = UrlFixture()..enabled = false; addTearDown(f.close);
    await f.login(); final r = await f.open(); final before = await f.urls.read(r);
    await expectLater(f.urls.save(r, before, join), throwsStateError);
    expect(f.saves, 0);
  });
  test('wrong company response does not produce a blank writable snapshot', () async {
    final f = UrlFixture()..wrongCompany = true; addTearDown(f.close);
    await f.login(); final r = await f.open();
    await expectLater(f.urls.read(r), throwsStateError); expect(f.saves, 0);
  });
  test('lost ACK persists only lookup identifiers, restart/OFF lookup resolves without resend', () async {
    final f = UrlFixture()..loseAck = true; addTearDown(f.close);
    await f.login(); final r = await f.open(); final before = await f.urls.read(r);
    await expectLater(f.urls.save(r, before, join), throwsA(isA<http.ClientException>()));
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString(prefs.getKeys().single)!;
    expect(persisted, isNot(contains(join))); expect(persisted, isNot(contains('synthetic')));
    expect(persisted, isNot(contains('Bearer')));
    f.urls = EmployeeDistributionUrlRepository(f.client); await f.urls.initialize(r);
    f.enabled = false; f.unobserved = true;
    await expectLater(f.urls.inspectUnknownResult(r), throwsStateError);
    await expectLater(f.urls.save(r, before, join), throwsStateError);
    expect(f.urls.hasUnknownResult, true); expect(f.saves, 1);
    f.unobserved = false;
    expect(await f.urls.inspectUnknownResult(r), 'saved');
    expect(f.saves, 1); expect(f.urls.hasUnknownResult, false);
  });
  for (final terminal in ['error', 'done', 'SID ABA']) {
    test('late receipt after $terminal keeps durable unknown and never resends', () async {
      final f = UrlFixture()..barrier = Completer<void>(); addTearDown(f.close);
      await f.login(); final r = await f.open(); final before = await f.urls.read(r);
      final saving = f.urls.save(r, before, join);
      final checked = expectLater(saving, throwsStateError);
      while (f.saves == 0) { await Future<void>.delayed(Duration.zero); }
      if (terminal == 'error') { f.events.addError(StateError('synthetic')); }
      else if (terminal == 'done') { await f.events.close(); }
      else { f.session = fixture.nextSid; await f.login(); r.observeSession(f.client.auth.currentSession);
        f.session = fixture.sid; await f.login(); r.observeSession(f.client.auth.currentSession); }
      f.barrier!.complete(); await checked;
      expect(f.urls.hasUnknownResult, true); expect(f.saves, 1);
      expect((await SharedPreferences.getInstance()).getKeys(), isNotEmpty);
    });
  }
  test('confirmed CAS conflict resolves journal and requires fresh snapshot', () async {
    final f = UrlFixture()..conflict = true; addTearDown(f.close);
    await f.login(); final r = await f.open(); final before = await f.urls.read(r);
    expect(await f.urls.save(r, before, join), 'conflict');
    expect(f.urls.hasUnknownResult, false); expect(f.saves, 1);
  });
}
