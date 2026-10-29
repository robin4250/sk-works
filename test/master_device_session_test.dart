import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_device_management_page.dart';
import 'package:sk_works/features/settings/master_device_repository.dart';

const actor = '80000000-0000-0000-0000-000000000001';
Map<String, dynamic> session(String sid) {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {'access_token': '${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token':'synthetic-$sid','token_type':'bearer','expires_in':3600,
    'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-29T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
class Fixture {
  late SupabaseClient client;
  final calls = <http.Request>[];
  Completer<void>? rowsWait, capabilityWait, mutationWait;
  Future<void> login(String sid) => client.auth.setInitialSession(jsonEncode(session(sid)));
  static Future<Fixture> create() async {
    final f = Fixture();
    f.client = SupabaseClient('https://master-session.invalid','public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken:false),
      httpClient: MockClient((r) async {
        f.calls.add(r); dynamic result;
        switch (r.url.path.split('/').last) {
          case 'current_master_admin_status': result = {'is_master_admin':true};
          case 'master_device_rows':
            if (f.rowsWait != null) await f.rowsWait!.future;
            result = [for (final id in ['a','b']) {'id':id,'device_name':'device-$id','device_type':'mac','registered_at':'2026-10-29T00:00:00Z','is_locked':false}];
          case 'master_device_lock_capability':
            if (f.capabilityWait != null) await f.capabilityWait!.future;
            result = {'protocol':'sko-master-device-lock-v1','enabled':false};
          case 'revoke_master_device':
          case 'set_master_device_locked':
            if (f.mutationWait != null) await f.mutationWait!.future;
            result = null;
          default: throw StateError('Unexpected fixture RPC ${r.url.path}');
        }
        return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:r);
      }));
    await f.login('sid-a'); return f;
  }
  int get writes => calls.where((r)=>r.url.path.endsWith('revoke_master_device') || r.url.path.endsWith('set_master_device_locked')).length;
}
Future<void> open(WidgetTester t, Fixture f) async {
  await t.pumpWidget(MaterialApp(home:MasterDeviceManagementPage(repository:MasterDeviceRepository.forTesting(f.client))));
  await t.pumpAndSettle();
}
Future<void> close(WidgetTester t, Fixture f) async {
  await t.pumpWidget(const SizedBox()); await t.pump(); await t.runAsync(f.client.dispose);
}
void main() {
  testWidgets('actual SDK same UID SID A to B to A during revoke confirmation never mutates', (t) async {
    final f = (await t.runAsync(Fixture.create))!; await open(t,f);
    await t.tap(find.widgetWithText(OutlinedButton,'登録解除').first); await t.pumpAndSettle();
    await t.runAsync(() async { await f.login('sid-b'); await f.login('sid-a'); });
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton,'登録解除')); await t.pumpAndSettle();
    expect(f.writes,0); await close(t,f);
  });
  testWidgets('actual SDK same UID new SID during capability cannot dispatch lock', (t) async {
    final f = (await t.runAsync(Fixture.create))!; await open(t,f); f.capabilityWait=Completer<void>();
    await t.tap(find.widgetWithText(OutlinedButton,'ロック').first); await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton,'ロック')); await t.pump();
    await t.runAsync(() => f.login('sid-b')); f.capabilityWait!.complete(); await t.pumpAndSettle();
    expect(f.writes,0); await close(t,f);
  });
  testWidgets('actual SDK delayed rows from old SID never display after switch', (t) async {
    final f = (await t.runAsync(Fixture.create))!; f.rowsWait=Completer<void>();
    await t.pumpWidget(MaterialApp(home:MasterDeviceManagementPage(repository:MasterDeviceRepository.forTesting(f.client))));
    await t.pump(); await t.pump(const Duration(milliseconds:10));
    await t.runAsync(() => f.login('sid-b')); f.rowsWait!.complete(); await t.pumpAndSettle();
    expect(find.text('device-a'),findsNothing); await close(t,f);
  });
  testWidgets('committed mutation followed by SID change never reloads or reports success', (t) async {
    final f = (await t.runAsync(Fixture.create))!; await open(t,f); f.mutationWait=Completer<void>();
    await t.tap(find.widgetWithText(OutlinedButton,'登録解除').first); await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton,'登録解除')); await t.pump();
    final original = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    final sent = f.calls.singleWhere((r)=>r.url.path.endsWith('revoke_master_device'));
    expect(sent.headers['Authorization'],original);
    final count = f.calls.length;
    await t.runAsync(() => f.login('sid-b')); f.mutationWait!.complete(); await t.pumpAndSettle();
    expect(f.writes,1); expect(f.calls.length,count);
    expect(find.text('端末登録を解除しました'),findsNothing); expect(find.text('device-a'),findsNothing);
    await close(t,f);
  });
  testWidgets('disposed page ignores late list completion', (t) async {
    final f = (await t.runAsync(Fixture.create))!; f.rowsWait=Completer<void>();
    await t.pumpWidget(MaterialApp(home:MasterDeviceManagementPage(repository:MasterDeviceRepository.forTesting(f.client))));
    await t.pump(); await t.pump(const Duration(milliseconds:10));
    await t.pumpWidget(const SizedBox()); f.rowsWait!.complete(); await t.pumpAndSettle();
    expect(t.takeException(),isNull); await t.runAsync(f.client.dispose);
  });
  test('actual SDK dispatch respects captured bearer even when SDK currently has another SID', () async {
    final f=await Fixture.create(); addTearDown(f.client.dispose);
    final original=f.client.auth.currentSession!;
    final changes=StreamController<AuthState>.broadcast(); addTearDown(changes.close);
    final binding=MasterDeviceSession(currentSession:()=>original,changes:changes.stream);
    addTearDown(binding.close);
    await f.login('sid-b');
    await MasterDeviceRepository.forTesting(f.client).revoke('a',session:binding);
    expect(f.calls.single.headers['Authorization'],'Bearer ${original.accessToken}');
    expect(f.client.auth.currentSession!.accessToken,isNot(original.accessToken));
  });
  test('first exact signedIn replay allowed; later same object signedIn invalidates permanently', () async {
    final f=await Fixture.create(); addTearDown(f.client.dispose);
    final original=f.client.auth.currentSession!;
    final changes=StreamController<AuthState>.broadcast(); addTearDown(changes.close);
    final binding=MasterDeviceSession(currentSession:()=>original,changes:changes.stream);
    addTearDown(binding.close);
    changes.add(AuthState(AuthChangeEvent.signedIn,original)); await binding.check();
    expect(binding.isCurrent,isTrue);
    changes.add(AuthState(AuthChangeEvent.signedIn,original));
    await expectLater(binding.check(),throwsStateError);
    expect(binding.isCurrent,isFalse);
  });
  test('first signedIn replay must be exact Session, and token refresh retains captured bearer', () async {
    final f=await Fixture.create(); addTearDown(f.client.dispose);
    final original=f.client.auth.currentSession!;
    final copy=Session.fromJson(session('sid-a'))!;
    final changes=StreamController<AuthState>.broadcast(); addTearDown(changes.close);
    Session current=original;
    final binding=MasterDeviceSession(currentSession:()=>current,changes:changes.stream);
    addTearDown(binding.close);
    current=copy; changes.add(AuthState(AuthChangeEvent.tokenRefreshed,copy)); await binding.check();
    expect(binding.accessToken,original.accessToken);
    final otherChanges=StreamController<AuthState>.broadcast(); addTearDown(otherChanges.close);
    final other=MasterDeviceSession(currentSession:()=>original,changes:otherChanges.stream); addTearDown(other.close);
    otherChanges.add(AuthState(AuthChangeEvent.signedIn,copy));
    await expectLater(other.check(),throwsStateError);
  });

}
