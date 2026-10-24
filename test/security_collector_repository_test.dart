import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/security/security_collector_repository.dart';

Map<String, dynamic> snapshot() => {'version':1,
  'source_provenance':'trusted_collector_observation',
  'coverage':'collector_observations_only','attack_confirmed':false,'events':[]};

void main() {
  late StreamController<void> changes;
  late String? key;
  late int issued, reads;
  late bool allowed, active;
  late SecurityCollectorRepository repository;
  setUp(() {
    changes = StreamController<void>.broadcast(sync:true);
    key = 'master/session-a'; issued = 0; reads = 0; allowed = true; active = true;
    repository = SecurityCollectorRepository(sessionKey: () => key,
      sessionChanges: changes.stream,
      availableCheck: () async => allowed,
      issueProof: (_) async { issued++; return 'a' * 64; },
      readWithProof: (proof) async { expect(proof, 'a' * 64); reads++; return snapshot(); });
  });
  tearDown(() async { await changes.close(); });

  test('each explicit read obtains one proof and sends it only to fixed reader', () async {
    expect((await repository.load('password')).events, isEmpty);
    await repository.load('password');
    expect(issued, 2); expect(reads, 2);
  });
  test('ordinary authorization denial does not issue a proof', () async {
    allowed = false;
    expect(await repository.available(), isFalse);
    await expectLater(repository.load('password'), throwsA(isA<SecurityCollectorUnavailable>()));
    expect(issued,0); expect(reads,0);
  });
  test('session changes and returns during proof issuance cannot consume proof', () async {
    final proof = Completer<String>();
    repository = SecurityCollectorRepository(sessionKey: () => key, sessionChanges: changes.stream,
      availableCheck: () async => true, issueProof: (_) => proof.future,
      readWithProof: (_) async { reads++; return snapshot(); });
    final work = repository.load('password');
    final result = expectLater(work, throwsA(isA<SecurityCollectorUnavailable>()));
    await Future<void>.delayed(Duration.zero);
    key = 'other/session-b'; changes.add(null);
    key = 'master/session-a'; changes.add(null);
    proof.complete('a' * 64); await result; expect(reads,0);
  });
  test('cancelled caller refuses consume after issuance', () async {
    final proof = Completer<String>();
    repository = SecurityCollectorRepository(sessionKey: () => key, sessionChanges: changes.stream,
      availableCheck: () async => true, issueProof: (_) => proof.future,
      readWithProof: (_) async { reads++; return snapshot(); });
    final work = repository.load('password', isActive: () => active);
    final result = expectLater(work, throwsA(isA<SecurityCollectorUnavailable>()));
    await Future<void>.delayed(Duration.zero); active = false;
    proof.complete('a' * 64); await result; expect(reads,0);
  });
  test('missing public RPC is unavailable and never retries the proof', () async {
    repository = SecurityCollectorRepository(sessionKey: () => key, sessionChanges: changes.stream,
      availableCheck: () async => true, issueProof: (_) async { issued++; return 'a' * 64; },
      readWithProof: (_) async { reads++; throw const PostgrestException(message:'missing',code:'PGRST202'); });
    await expectLater(repository.load('password'), throwsA(isA<SecurityCollectorUnavailable>()));
    expect(issued,1); expect(reads,1);
  });
  test('unknown and wrong-scope responses are not rendered', () {
    for (final invalid in [<String,dynamic>{}, {...snapshot(),'scope':'platform'},
      {...snapshot(),'attack_confirmed':true}, {...snapshot(),'source_provenance':'supabase_platform_logs'},
      {...snapshot(),'events':List.filled(101,{})}]) {
      expect(() => SecurityCollectorSnapshot.parse(invalid), throwsFormatException);
    }
  });
  test('exact existing consumer event schema is accepted without claiming attack', () {
    final event = {'event_id':'00000000-0000-0000-0000-000000000001',
      'collector_id':'00000000-0000-0000-0000-000000000002',
      'occurred_at':'2026-10-25T00:01:00+00:00','received_at':'2026-10-25T00:01:01+00:00',
      'event_kind':'current_lure_touched','generation':1,'correlation_key':'b'*64,
      'key_epoch':'2026-10-25','source_provenance':'trusted_collector_observation'};
    final parsed = SecurityCollectorSnapshot.parse({...snapshot(),'events':[event]});
    expect(parsed.events.single,event);
    expect(() => parsed.events.clear(),throwsUnsupportedError);
    expect(() => parsed.events.single['password']='secret',throwsUnsupportedError);
  });
  test('malformed event including secret fields is refused', () {
    expect(() => SecurityCollectorSnapshot.parse({...snapshot(),'events':[{'password':'secret'}]}), throwsFormatException);
  });
}
