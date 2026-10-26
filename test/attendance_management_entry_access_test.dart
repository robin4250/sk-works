import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/attendance/attendance_management_entry_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'operation_reauthentication_repository_test.dart' as base;

const company = '30000000-0000-0000-0000-000000000001';
class EntryFixture extends base.Fixture {
  late final access = AttendanceManagementEntryAccess(client);
  Object entryCapability = {'protocol': 'sko-attendance-entry-v1', 'enabled': true,
    'company_id': company, 'ttl_seconds': 900};
  int status = 200;
  bool passwordAccepted = true;
  bool writeFails = false;
  int expirySeconds = 900;
  Future<void> Function()? duringOpen;
  Future<void> Function()? duringWrite;
  final entryCalls = <http.Request>[];
  @override Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/attendance_management_entry_capabilities')) {
      entryCalls.add(request);
      return base.jsonResponse(entryCapability, status);
    }
    if (request.url.path.endsWith('/open_attendance_management_access')) {
      entryCalls.add(request);await duringOpen?.call();
      return base.jsonResponse(passwordAccepted
          ? {'protocol': 'sko-attendance-entry-v1', 'ok': true, 'company_id': company,
            'grant': List.filled(64, 'c').join(),
            'expires_at': DateTime.now().add(Duration(seconds: expirySeconds)).toIso8601String()}
          : {'protocol': 'sko-attendance-entry-v1', 'ok': false, 'error': 'invalid_password'});
    }
    if (request.url.path.endsWith('/force_manage_attendance_with_access')) {
      entryCalls.add(request);await duringWrite?.call();
      return writeFails ? base.jsonResponse({'code': '42501', 'message': 'attendance_entry_access_required'},403)
          : base.jsonResponse(1);
    }
    if (request.url.path.endsWith('/close_attendance_management_access')) {
      entryCalls.add(request);return base.jsonResponse({});
    }
    return super.handle(request);
  }
  Future<void> cleanup() async {await access.close();await client.dispose();}
  Future<void> enter() async {await login();await access.prepare();}
  Future<int> write([String action = 'upsert']) => access.manage(action: action,
    items: [{'worker_id': 'synthetic-worker', 'date': '2026-10-26', 'mode': action == 'delete' ? 'off' : 'work'}]);
}
void main() {
  test('one entry password authorizes multiple actual SDK writes without further credential requests', () async {
    final f=EntryFixture();addTearDown(f.cleanup);await f.enter();
    expect(f.access.requiredByServer,true);expect(f.access.isOpen,false);
    expect(await f.access.unlock('synthetic-entry-password'),true);
    expect(await f.write(),1);expect(await f.write(),1);expect(await f.write('delete'),1);
    final opens=f.entryCalls.where((r)=>r.url.path.endsWith('/open_attendance_management_access')).toList();
    final writes=f.entryCalls.where((r)=>r.url.path.endsWith('/force_manage_attendance_with_access')).toList();
    expect(opens,hasLength(1));expect(writes,hasLength(3));
    expect(jsonDecode(opens.single.body),{'p_password':'synthetic-entry-password','p_expected_company_id':company});
    for(final request in writes) {
      final body=jsonDecode(request.body) as Map;
      expect(body['p_access'],List.filled(64,'c').join());expect(body['p_expected_company_id'],company);
      expect(body.containsKey('p_password'),false);
    }
    expect(f.bodies,isEmpty,reason:'No per-operation Edge password/proof request');
  });
  test('wrong password leaves entry locked and performs no management write', () async {
    final f=EntryFixture()..passwordAccepted=false;addTearDown(f.cleanup);await f.enter();
    expect(await f.access.unlock('synthetic-wrong'),false);expect(f.access.isOpen,false);
    await expectLater(f.write(),throwsStateError);
    expect(f.entryCalls.where((r)=>r.url.path.endsWith('/force_manage_attendance_with_access')),isEmpty);
  });
  test('only missing additive capability API permits OFF compatibility', () async {
    final f=EntryFixture();addTearDown(f.cleanup);await f.login();
    f.status=404;f.entryCapability={'code':'PGRST202','message':'synthetic missing API'};
    await f.access.prepare();expect(f.access.requiredByServer,false);
    f.status=403;f.entryCapability={'code':'42501','message':'synthetic denial'};
    await expectLater(f.access.prepare(),throwsA(isA<PostgrestException>()));
    f.status=200;f.entryCapability={'protocol':'sko-attendance-entry-v1','enabled':'true','company_id':company,'ttl_seconds':900};
    await expectLater(f.access.prepare(),throwsStateError);
  });
  test('background or route invalidation discards grant and late management response', () async {
    final f=EntryFixture();addTearDown(f.cleanup);await f.enter();await f.access.unlock('synthetic-entry-password');
    f.duringWrite=() async {f.access.invalidate();};
    await expectLater(f.write(),throwsStateError);expect(f.access.isOpen,false);
    final writes=f.entryCalls.where((r)=>r.url.path.endsWith('/force_manage_attendance_with_access')).length;
    await expectLater(f.write(),throwsStateError);
    expect(f.entryCalls.where((r)=>r.url.path.endsWith('/force_manage_attendance_with_access')).length,writes);
  });
  test('historical A to B to A during entry cannot adopt old grant', () async {
    final f=EntryFixture();addTearDown(f.cleanup);await f.enter();
    f.duringOpen=() async {
      f.actor=base.actorB;f.session=base.sessionB;await f.login();
      f.actor=base.actorA;f.session=base.sessionA;await f.login();
    };
    await expectLater(f.access.unlock('synthetic-entry-password'),throwsStateError);
    expect(f.access.isOpen,false);
  });
  test('expired or overlong grant and server denial never downgrade to old writer', () async {
    final f=EntryFixture();addTearDown(f.cleanup);await f.enter();
    for(final seconds in [-1,1000]) {
      f.expirySeconds=seconds;await expectLater(f.access.unlock('synthetic-entry-password'),throwsStateError);
    }
    f.expirySeconds=900;await f.access.unlock('synthetic-entry-password');f.writeFails=true;
    await expectLater(f.write(),throwsA(isA<PostgrestException>()));expect(f.access.isOpen,false);
    expect(f.bodies,isEmpty);
  });
}
