import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/security/security_collector_repository.dart';

Map<String, dynamic> snapshot() => {'version':1,
  'source_provenance':'trusted_collector_observation',
  'coverage':'collector_observations_only','attack_confirmed':false,'events':[]};

void main() {
  late StreamController<String?> changes;
  late String? key;
  late int issued, reads;
  late bool allowed, active;
  late SecurityCollectorRepository repository;
  setUp(() {
    changes = StreamController<String?>.broadcast(sync:true);
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
    key = 'other/session-b'; changes.add(key);
    key = 'master/session-a'; changes.add(key);
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
  for(final transition in ['same-user-session-hop','signed-out-and-restored']) {
    test('async $transition cannot be collapsed into the current restored session', () async {
      final events=StreamController<String?>.broadcast(); // SDK default is async
      final issuing=Completer<void>(),proof=Completer<String>();
      repository=SecurityCollectorRepository(sessionKey:()=>key,sessionChanges:events.stream,
        availableCheck:() async=>true,
        issueProof:(_) {issuing.complete();return proof.future;},
        readWithProof:(_) async {reads++;return snapshot();});
      final work=repository.load('password');
      final denied=expectLater(work,throwsA(isA<SecurityCollectorUnavailable>()));
      await issuing.future;
      if(transition=='same-user-session-hop') {
        key='master/session-b';events.add(key);
      } else { key=null;events.add(null); }
      key='master/session-a';events.add(key);
      // Both queued callbacks observe current A. Only each emitted event key
      // can prove that session B (or signed-out null) was crossed in between.
      await Future<void>.delayed(Duration.zero);
      proof.complete('a'*64);await denied;
      expect(reads,0);await events.close();
    });
  }
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
  Map<String,dynamic> calendarEvent() => {
    'event_id':'00000000-0000-0000-0000-000000000001',
    'collector_id':'00000000-0000-0000-0000-000000000002',
    'occurred_at':'2026-10-25T00:01:00+00:00',
    'received_at':'2026-10-25T00:01:01.123456Z',
    'event_kind':'current_lure_touched','generation':1,'correlation_key':'b'*64,
    'key_epoch':'2026-10-25','source_provenance':'trusted_collector_observation',
  };
  test('audit key epoch refuses normalized nonexistent calendar dates', () {
    for(final value in ['2026-02-29','2026-02-31','2026-04-31',
      '2026-00-25','2026-13-01','2026-10-00','0000-10-25','2026-10-25\n']) {
      expect(()=>SecurityCollectorSnapshot.parse({...snapshot(),
        'events':[{...calendarEvent(),'key_epoch':value}]}),throwsFormatException,
        reason:value);
    }
  });
  test('audit timestamps require real calendar, clock and explicit zone', () {
    for(final field in ['occurred_at','received_at']) {
      for(final value in ['2026-02-31T00:00:00Z','2026-02-29T00:00:00Z',
        '2026-13-01T00:00:00Z','2026-10-25T24:00:00Z',
        '2026-10-25T00:60:00Z','2026-10-25T00:00:60Z',
        '2026-10-25T00:00:00+24:00','2026-10-25T00:00:00+00:60',
        '2026-10-25T00:00:00','2026-10-25','2026-10-25T00:00:00Z\n','PRIVATE_VALUE']) {
        expect(()=>SecurityCollectorSnapshot.parse({...snapshot(),
          'events':[{...calendarEvent(),field:value}]}),throwsFormatException,
          reason:'$field $value');
      }
    }
  });
  test('real leap date and PostgreSQL timestamps keep original evidence', () {
    for(final zone in ['Z','+00:00','+09:00','-05:30']) {
      final event={...calendarEvent(),'key_epoch':'2024-02-29',
        'occurred_at':'2024-02-29T23:59:59.123456$zone',
        'received_at':'2024-03-01T00:01:00$zone'};
      final parsed=SecurityCollectorSnapshot.parse({...snapshot(),'events':[event]});
      expect(parsed.events.single,event);
    }
  });
  test('malformed event including secret fields is refused', () {
    expect(() => SecurityCollectorSnapshot.parse({...snapshot(),'events':[{'password':'secret'}]}), throwsFormatException);
  });
}
