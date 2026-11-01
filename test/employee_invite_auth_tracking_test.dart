import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/employee_invite_repository.dart';
import 'employee_invite_context_sdk_test.dart' as fixture;

void main() {
  test('unavailable observation denies before SDK reads or invite mutation', () async {
    final f = fixture.Fixture();
    addTearDown(f.client.dispose);
    addTearDown(f.repository.dispose);
    await f.login();
    final r = EmployeeInviteRepository.forTesting(f.client, authEvents: null);
    addTearDown(r.dispose);
    final before = f.requests.length;
    await expectLater(r.beginRequest(), throwsStateError);
    expect(f.requests.length, before);
    expect(f.invokes, 0);
  });
  for (final failure in ['error', 'done']) {
    test('$failure permanently invalidates captured request despite SDK SID ABA', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      addTearDown(f.repository.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = EmployeeInviteRepository.forTesting(f.client, authEvents: events.stream);
      addTearDown(r.dispose);
      final request = await r.beginRequest();
      if (failure == 'error') { events.addError(StateError('synthetic observation failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.session = fixture.nextSid;
      await f.login();
      f.session = fixture.sid;
      await f.login();
      expect(request.check, throwsStateError);
      await expectLater(r.beginRequest(), throwsStateError);
      expect(f.invokes, 0);
    });
    test('$failure rejects late actual SDK invite response and does not resend', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      addTearDown(f.repository.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = EmployeeInviteRepository.forTesting(f.client, authEvents: events.stream);
      addTearDown(r.dispose);
      final request = await r.beginRequest();
      f.pending = Completer<http.Response>();
      final operation = r.createInvite(name: 'Synthetic Employee', phone: '07000000000', request: request);
      final rejected = expectLater(operation, throwsStateError);
      await f.issued.future;
      if (failure == 'error') { events.addError(StateError('synthetic observation failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.pending!.complete(http.Response(jsonEncode(fixture.result()), 200,
        headers: {'content-type': 'application/json'}));
      await rejected;
      await expectLater(r.createInvite(name: 'Synthetic Employee', phone: '07000000000', request: request), throwsStateError);
      expect(f.invokes, 1);
    });
  }
}
