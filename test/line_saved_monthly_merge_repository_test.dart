import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/auth/app_auth_logout_persistence.dart';
import 'package:sk_works/features/chat/line_saved_monthly_merge_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '20000000-0000-0000-0000-000000000001';
const target = '30000000-0000-0000-0000-000000000001';
const source = '30000000-0000-0000-0000-000000000002';
const another = '30000000-0000-0000-0000-000000000003';
final month = DateTime(2026, 10);

Map<String, dynamic> session(String sid) {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {'access_token': '${part({'alg': 'HS256'})}.${part({'sub': actor, 'role': 'authenticated', 'session_id': sid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token': 'synthetic-$sid', 'token_type': 'bearer', 'expires_in': 3600,
    'user': {'id': actor, 'aud': 'authenticated', 'created_at': '2026-11-01T00:00:00Z',
      'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}}};
}

class Fixture {
  late SupabaseClient client;
  late LineSavedMonthlyMergeRepository repository;
  final requests = <http.Request>[];
  final receipts = <String, Map<String, dynamic>>{};
  bool foreignSource = false, deniedGroup = false, duplicateMember = false;
  bool enabled = true, wrongResult = false, loseAck = false;
  bool numericRoundtrip = false, rejectNextSave = false, revokeAfterSave = false;
  bool legacySource = false;
  bool rawDenied = false;
  final rawPosts = <Map<String, dynamic>>[];
  String kind = 'history';
  String? role = 'owner';
  int committed = 0;
  Completer<void>? groupWait;
  Map<String, dynamic> workspace() => {'features': {'invoice': enabled, 'attendance': false},
    'can_edit': true, 'draft_id': null, 'revision': 0, 'source_kind': kind,
    'source_messages': <Map<String, dynamic>>[if (legacySource) {'id': 'legacy', 'body': 'original'}],
    'candidate_rows': <Map<String, dynamic>>[],
    'note_comparison': '', 'confirmed': false};
  Future<void> login(String sid) async { await client.auth.setInitialSession(jsonEncode(session(sid))); }
  static Future<Fixture> create() async {
    final f = Fixture();
    f.client = SupabaseClient('https://saved-month-fixture.invalid', 'synthetic_public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        f.requests.add(r);
        final endpoint = r.url.path.split('/').last;
        Object? body;
        switch (endpoint) {
          case 'communication_groups':
            await f.groupWait?.future;
            final id = r.url.queryParameters['id']!.substring(3);
            body = f.deniedGroup ? [] : [{'id': id, 'company_id': f.foreignSource && id == source
              ? '20000000-0000-0000-0000-000000000002' : company}];
          case 'company_members':
            final member = {'company_id': company, 'user_id': actor, 'role': f.role};
            body = [member, if (f.duplicateMember) member];
          case 'chat_messages':
            if (f.rawDenied) {
              return http.Response(jsonEncode({'code': '42501', 'message': 'denied'}), 403, headers: {'content-type': 'application/json'}, request: r);
            }
            body = f.rawPosts;
          case 'line_import_workspace': body = f.workspace();
          case 'line_history_destinations': body = [
            {'id': target, 'name': 'Synthetic receiving group'}, {'id': source, 'name': 'Synthetic saved group'}];
          case 'save_line_import_draft':
            if (f.rejectNextSave) {
              f.rejectNextSave = false;
              return http.Response(jsonEncode({'code': '40001', 'message': 'Synthetic stale revision'}),
                409, headers: {'content-type': 'application/json'}, request: r);
            }
            final command = jsonDecode(r.body) as Map<String, dynamic>;
            final id = command['p_command_id'] as String;
            body = f.receipts.putIfAbsent(id, () {
              f.committed++;
              return {...f.workspace(), 'draft_id': '40000000-0000-0000-0000-000000000001',
                'revision': (command['p_expected_revision'] as int) + 1,
                'source_kind': command['p_source_kind'], 'source_messages': command['p_sources'],
                'candidate_rows': command['p_rows'], 'note_comparison': command['p_note']};
            });
            if (f.loseAck) { f.loseAck = false; throw http.ClientException('Synthetic committed response lost'); }
            if (f.wrongResult) body = {...body as Map, 'candidate_rows': []};
            if (f.numericRoundtrip) {
              final normalized = <Map<String, dynamic>>[];
              for (final row in command['p_rows'] as List) {
                final copy = Map<String, dynamic>.from(row as Map);
                copy['man_days'] = 1.0;
                normalized.add(Map<String, dynamic>.fromEntries(copy.entries.toList().reversed));
              }
              body = {...body as Map, 'candidate_rows': normalized};
            }
            if (f.revokeAfterSave) f.role = 'viewer';
          default: throw StateError('Unexpected endpoint $endpoint');
        }
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: r);
      }));
    await f.login('sid-a');
    f.repository = LineSavedMonthlyMergeRepository.forClient(f.client);
    return f;
  }
  Future<Map<String, dynamic>> prepare() async {
    await repository.load(target, month); await repository.load(source, month);
    await repository.verifyGroups(target, source);
    return command();
  }
  Map<String, dynamic> command() => repository.saveCommand(groupId: target, target: 'invoice',
    month: month, revision: 0, sourceKind: 'history', sources: [
      {'id': 'saved:$source:original', 'body': '10/1\nSynthetic Site Synthetic Worker',
        'source_type': 'history', 'sent_at': '2026-11-01T00:00:00Z'}], rows: [
      {'row_id': 'saved:$source:original:0', 'source_message_id': 'saved:$source:original',
        'work_date': '2026-10-01', 'man_days': 1, 'confirmed': false}], note: 'retained note', confirmed: false);
  Future<void> close() async { await repository.close(); await client.dispose(); }
}

class PendingLogout implements AppLogoutPersistenceFence {
  final release = Completer<void>();
  @override bool blocked = false;
  @override Future<void> persistIntent() async { blocked = true; await release.future; throw StateError('Synthetic persistence denied'); }
  @override Future<void> confirmLocalRemoval() async => throw StateError('Unexpected local logout');
  @override Future<void> releaseFence(bool Function() confirmed) async => throw StateError('Unexpected release');
}

void main() {
  test(
    'raw-only saved group parses work month without source draft writes or upload',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.rawPosts.addAll([
        {
          'id': 'raw-oct',
          'body': '2026/10/1\n現場A 山田\n現場A 定時',
          'sent_at': '2026-11-01T09:00:00Z',
          'sender_display_name': '担当者',
        },
        {
          'id': 'raw-nov',
          'body': '2026/11/1\n現場B 山田\n現場B 定時',
          'sent_at': '2026-11-01T09:01:00Z',
          'sender_display_name': '担当者',
        },
      ]);
      final result = await f.repository.loadSource(source, month);
      final rows = result['candidate_rows'] as List;
      expect(rows, hasLength(1));
      expect(rows.single['work_date'], '2026-10-01');
      expect(rows.single['confirmed'], isFalse);
      expect(rows.single['source_message_id'], 'raw-oct');
      expect(f.committed, 0);
      final request = f.requests.singleWhere(
        (r) => r.url.path.endsWith('/chat_messages'),
      );
      expect(
        request.url.queryParameters['communication_group_id'],
        'eq.$source',
      );
      expect(request.url.queryParameters['origin'], 'eq.line');
      expect(request.url.queryParameters.containsKey('sent_at'), isFalse);
      expect(
        request.headers['Authorization'],
        'Bearer ${f.client.auth.currentSession!.accessToken}',
      );
    },
  );

  test(
    'denied raw read fails closed instead of reporting empty source',
    () async {
      final f = await Fixture.create();
      addTearDown(f.close);
      f.rawDenied = true;
      await expectLater(
        f.repository.loadSource(source, month),
        throwsA(isA<PostgrestException>()),
      );
      expect(f.committed, 0);
    },
  );


  test('actual SDK uses captured bearer and existing draft-only RPC without moving originals', () async {
    final f = await Fixture.create(); addTearDown(f.close);
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    final command = await f.prepare(); final result = await f.repository.save(command);
    expect(result['revision'], 1); expect(f.committed, 1);
    expect(f.requests.every((r) => r.headers['Authorization'] == bearer), isTrue);
    final writes = f.requests.where((r) => r.method == 'POST' && r.url.path.endsWith('save_line_import_draft')).toList();
    expect(writes, hasLength(1)); expect(jsonDecode(writes.single.body), command);
    expect(f.requests.any((r) => ['PATCH', 'DELETE', 'PUT'].contains(r.method)), isFalse);
    expect(f.requests.any((r) => r.url.path.contains('create_line_invoices') || r.url.path.contains('submit_line')), isFalse);
  });
  for (final boundary in ['foreign', 'missing', 'duplicate', 'null-role', 'viewer', 'disabled']) {
    test('$boundary cannot save or masquerade as empty authorized source', () async {
      final f = await Fixture.create(); addTearDown(f.close);
      f.foreignSource = boundary == 'foreign'; f.deniedGroup = boundary == 'missing';
      f.duplicateMember = boundary == 'duplicate'; f.role = boundary == 'null-role' ? null : boundary == 'viewer' ? 'viewer' : 'owner';
      f.enabled = boundary != 'disabled';
      await expectLater(f.prepare(), throwsStateError); expect(f.committed, 0);
    });
  }
  test('target, month, command and formal confirmation are bound to the verified preview', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare();
    for (final changed in [
      {...command, 'p_group_id': another}, {...command, 'p_month': '2026-11-01'},
      {...command, 'p_target': 'attendance'}, {...command, 'p_confirmed': true},
      {...command, 'p_rows': []},
    ]) { await expectLater(f.repository.save(changed), throwsStateError); }
    expect(f.committed, 0);
  });
  test('membership revoked after preview prevents the draft RPC', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare();
    f.role = 'viewer'; await expectLater(f.repository.save(command), throwsStateError); expect(f.committed, 0);
  });
  test('loading either group in a different month cannot submit the earlier prepared month', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare();
    for (final group in [target, source]) {
      await f.repository.load(group, DateTime(2026, 11));
      await expectLater(f.repository.save(command), throwsStateError);
      expect(f.committed, 0);
      await f.repository.load(group, month);
    }
  });
  test('lost ACK retains exact command and existing receipt is reused, never blind new command', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare(); f.loseAck = true;
    await expectLater(f.repository.save(command), throwsA(isA<http.ClientException>())); expect(f.committed, 1);
    await expectLater(f.repository.save(f.command()), throwsStateError); expect(f.committed, 1);
    expect((await f.repository.save(command))['revision'], 1); expect(f.committed, 1);
  });
  test('mismatched save response is not reported as successful', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare(); f.wrongResult = true;
    await expectLater(f.repository.save(command), throwsStateError); expect(f.committed, 1);
  });
  test('JSONB numeric normalization and map key order do not cause a false unknown result', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare(); f.numericRoundtrip = true;
    expect((await f.repository.save(command))['revision'], 1); expect(f.committed, 1);
  });
  test('explicit stale-revision rejection permits a freshly reviewed command', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare(); f.rejectNextSave = true;
    await expectLater(f.repository.save(command), throwsA(isA<PostgrestException>())); expect(f.committed, 0);
    final fresh = await f.prepare(); expect((await f.repository.save(fresh))['revision'], 1); expect(f.committed, 1);
  });
  test('scope denial after a committed save is not confused with an RPC rollback', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare(); f.revokeAfterSave = true;
    await expectLater(f.repository.save(command), throwsStateError); expect(f.committed, 1);
    f.role = 'owner'; f.revokeAfterSave = false;
    await f.repository.verifyGroups(target, source);
    await expectLater(f.repository.save(f.command()), throwsStateError); expect(f.committed, 1);
    expect((await f.repository.save(command))['revision'], 1); expect(f.committed, 1);
  });
  test('SID A-B-A during actual group request permanently retires repository', () async {
    final f = await Fixture.create(); addTearDown(f.close); f.groupWait = Completer<void>();
    final pending = f.repository.load(target, month);
    for (var i = 0; i < 1000 && f.requests.isEmpty; i++) { await Future<void>.delayed(const Duration(milliseconds: 1)); }
    expect(f.requests, isNotEmpty); await f.login('sid-b'); await f.login('sid-a'); f.groupWait!.complete();
    await expectLater(pending, throwsStateError); expect(f.repository.isCurrent, isFalse);
    await expectLater(f.repository.load(target, month), throwsStateError); expect(f.committed, 0);
  });
  test('pending and failed logout quarantine deny requests even with unchanged SDK token', () async {
    final f = await Fixture.create(); addTearDown(f.close); await f.prepare(); f.requests.clear();
    final fence = PendingLogout(); final owner = AppAuthMutationGateway.bindPersistence(f.client, fence);
    final logout = owner.signOut(); final failed = expectLater(logout, throwsStateError);
    await expectLater(f.repository.destinations(), throwsStateError); expect(f.requests, isEmpty);
    fence.release.complete(); await failed;
    await expectLater(f.repository.destinations(), throwsStateError); expect(f.requests, isEmpty);
  });
  test('same-company source selection may change before save but old preview cannot be used', () async {
    final f = await Fixture.create(); addTearDown(f.close); final command = await f.prepare();
    await f.repository.load(another, month); await f.repository.verifyGroups(target, another);
    await expectLater(f.repository.save(command), throwsStateError); expect(f.committed, 0);
  });
  for (final kind in ['received', 'history', 'mixed']) {
    test('legacy missing source_type is recovered only from unambiguous $kind source kind', () async {
      final f = await Fixture.create(); addTearDown(f.close); f.legacySource = true; f.kind = kind;
      if (kind == 'mixed') {
        await expectLater(f.repository.load(target, month), throwsStateError);
      } else {
        final data = await f.repository.load(target, month);
        expect((data['source_messages'] as List).single['source_type'], kind);
      }
      expect(f.committed, 0);
    });
  }
}
