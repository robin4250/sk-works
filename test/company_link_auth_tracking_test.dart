import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';
import 'company_link_bound_sdk_test.dart' as fixture;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('unavailable observation denies before company reads or RPC', () async {
    final f = fixture.Fixture();
    addTearDown(f.client.dispose);
    await f.login();
    final r = TradeCompanyRepository.forTesting(f.client, authEvents: () => null);
    final before = f.requests.length;
    await expectLater(r.openBoundLinkContext(), throwsStateError);
    expect(f.requests.length, before);
    expect(f.mutations, 0);
  });
  for (final failure in ['error', 'done']) {
    test('$failure denies later commands despite SDK SID ABA', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = TradeCompanyRepository.forTesting(f.client, authEvents: () => events.stream);
      final context = await r.openBoundLinkContext();
      addTearDown(context.dispose);
      if (failure == 'error') { events.addError(StateError('synthetic tracking failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.session = fixture.sid2;
      await f.login();
      f.session = fixture.sid;
      await f.login();
      expect(context.isCurrent, false);
      await expectLater(context.mutate('set_enabled', {'enabled': true}), throwsStateError);
      expect(f.mutations, 0);
    });
    test('$failure rejects late receipt, preserves pending journal and fresh context only reconciles', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = TradeCompanyRepository.forTesting(f.client, authEvents: () => events.stream);
      final context = await r.openBoundLinkContext();
      addTearDown(context.dispose);
      f.pending = Completer<http.Response>();
      final operation = context.mutate('set_enabled', {'enabled': true});
      final rejected = expectLater(operation, throwsStateError);
      await f.arrived.future;
      if (failure == 'error') { events.addError(StateError('synthetic tracking failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.pending!.complete(http.Response(jsonEncode(f.envelope(f.saved!, {'state': 'committed', 'enabled': true})), 200,
        headers: {'content-type': 'application/json'},
        request: f.requests.firstWhere((r) => r.url.path.endsWith('company_link_bound_v1'))));
      await rejected;
      expect(context.hasUnknownResult, true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isNotEmpty);
      final fresh = await f.repository.openBoundLinkContext();
      addTearDown(fresh.dispose);
      await expectLater(fresh.mutate('set_enabled', {'enabled': false}), throwsStateError);
      expect((await fresh.inspectUnknownResult())['state'], 'committed');
      expect(f.mutations, 1);
      expect(prefs.getKeys(), isEmpty);
    });
  }
}
