import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Test-only platform fault injection below the real legacy preferences cache.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_logout_persistence.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

class Markers implements AppLogoutMarkerStore {
  String? value;
  bool writeOk=true, clearOk=true, readError=false, initError=false;
  Completer<void>? clearGate;
  @override Future<void> initialize() async { if(initError) throw StateError('marker unavailable'); }
  @override Future<String?> read() async { if(readError) throw StateError('marker unavailable'); return value; }
  @override Future<bool> writePending() async { if(writeOk) value='pending-v1'; return writeOk; }
  @override Future<bool> clear() async { await clearGate?.future; if(clearOk) value=null; return clearOk; }
}
class Disk extends LocalStorage {
  String? value;
  int saves=0, removes=0;
  bool removeError=false, lie=false, hasError=false, accessError=false, hideHas=false;
  Completer<void>? saveGate;
  @override Future<void> initialize() async {}
  @override Future<bool> hasAccessToken() async { if(hasError) throw StateError('storage read unavailable'); return !hideHas && value!=null; }
  @override Future<String?> accessToken() async { if(accessError) throw StateError('storage read unavailable'); return value; }
  @override Future<void> persistSession(String text) async { saves++; await saveGate?.future; value=text; }
  @override Future<void> removePersistedSession() async { removes++; if(removeError) throw StateError('storage unavailable'); if(!lie) value=null; }
}
class RefusingSessionRemoval extends InMemorySharedPreferencesStore {
  RefusingSessionRemoval(this.sessionKey, Map<String,Object> values):super.withData(values);
  final String sessionKey;
  @override Future<bool> remove(String key) async {
    if(key == 'flutter.$sessionKey') return false;
    return super.remove(key);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uninitialized wrapper never discloses or overwrites stored session',() async {
    final disk=Disk()..value='synthetic-original';
    final storage=AppAuthLogoutPersistence(delegate:disk,markers:Markers());
    expect(await storage.hasAccessToken(),false); expect(await storage.accessToken(),isNull);
    await storage.persistSession('synthetic-uninitialized');
    expect(disk.value,'synthetic-original'); expect(disk.saves,0);
  });
  for(final marker in <String?>[null,'pending-v1','unknown','']) {
    test('cold start gate distinguishes absent from marker $marker',() async {
      final disk=Disk()..value='synthetic-original'; final markers=Markers()..value=marker;
      final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize();
      expect(await storage.hasAccessToken(),marker==null);
      expect(await storage.accessToken(),marker==null?'synthetic-original':null);
      expect(disk.value,'synthetic-original');
    });
  }
  for(final initialization in [false,true]) {
    test('marker read/init error blocks restoration and survives retry',() async {
      final disk=Disk()..value='synthetic-original'; final markers=Markers()..readError=!initialization..initError=initialization;
      final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize();
      expect(storage.blocked,true); expect(await storage.accessToken(),isNull);
      markers.readError=false; markers.initError=false;
      await storage.persistIntent(); await storage.confirmLocalRemoval(); await storage.releaseFence(()=>true);
      expect(storage.blocked,false); expect(disk.value,isNull);
    });
  }
  test('failed marker ACK does not delete original or reopen gateway',() async {
    final disk=Disk()..value='synthetic-original'; final markers=Markers()..writeOk=false;
    final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize();
    final w=fixture.Wire();
    try {
      await w.seed(); final auth=AppAuthMutationGateway.bindPersistence(w.client,storage);
      await expectLater(auth.signOut(),throwsStateError);
      expect(auth.logoutQuarantine.state,AppLogoutQuarantineState.failed);
      expect(disk.value,'synthetic-original'); expect(disk.removes,0); expect(w.calls,isEmpty);
      await expectLater(w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic'),throwsStateError);
      expect(await storage.accessToken(),isNull);
    } finally { await w.client.dispose(); }
  });
  test('in-flight SDK save drains before marker and removal; queued late saves never revive session',() async {
    final disk=Disk()..saveGate=Completer<void>(); final markers=Markers();
    final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize();
    final save=storage.persistSession('synthetic-inflight'); await Future<void>.value();
    final intent=storage.persistIntent();
    final late=storage.persistSession('synthetic-late');
    expect(storage.blocked,true);
    disk.saveGate!.complete(); await save; await intent; await late;
    await storage.confirmLocalRemoval(); await storage.releaseFence(()=>true);
    expect(disk.saves,1); expect(disk.value,isNull); expect(markers.value,isNull);
  });
  for(final mode in ['throw','readback','clear','marker_read','has_error','access_error','mismatch']) {
    test('deletion/readback/marker release $mode failure retains fence',() async {
      final disk=Disk()..value='synthetic-original'; final markers=Markers();
      final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize(); await storage.persistIntent();
      disk.removeError=mode=='throw'; disk.lie=mode=='readback'||mode=='mismatch'; markers.clearOk=mode!='clear';
      markers.readError=mode=='marker_read'; disk.hasError=mode=='has_error'; disk.accessError=mode=='access_error'; disk.hideHas=mode=='mismatch';
      await expectLater(storage.releaseFence(()=>true),throwsStateError);
      expect(storage.blocked,true); expect(markers.value,'pending-v1'); expect(await storage.accessToken(),isNull);
    });
  }
  test('logout proof drift while marker clearing rearms persistent fence and suppresses late write',() async {
    final disk=Disk(); final markers=Markers()..clearGate=Completer<void>();
    final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize(); await storage.persistIntent();
    var proof=true; final release=storage.releaseFence(()=>proof); final rejected=expectLater(release,throwsStateError);
    await Future<void>.value(); proof=false;
    await storage.persistSession('synthetic-late'); markers.clearGate!.complete(); await rejected;
    expect(storage.blocked,true); expect(markers.value,'pending-v1'); expect(disk.value,isNull);
  });
  test('new intent during delayed release cannot open the newer storage generation',() async {
    final disk=Disk(); final markers=Markers()..clearGate=Completer<void>();
    final storage=AppAuthLogoutPersistence(delegate:disk,markers:markers); await storage.initialize(); await storage.persistIntent();
    final release=storage.releaseFence(()=>true); final rejected=expectLater(release,throwsStateError);
    await Future<void>.value(); final newer=storage.persistIntent();
    markers.clearGate!.complete(); await rejected; await newer;
    await storage.persistSession('synthetic-late');
    expect(storage.blocked,true); expect(markers.value,'pending-v1'); expect(disk.value,isNull);
  });
  test('real SharedPreferences storage preserves exact default key and unrelated preferences',() async {
    const url='https://storage-project.supabase.co'; final key=AppAuthLogoutPersistence.sdkSessionKey(url);
    expect(key,'sb-storage-project-auth-token');
    SharedPreferences.setMockInitialValues({key:'synthetic-existing','unrelated':'keep'});
    final storage=AppAuthLogoutPersistence.forProject(url); await storage.initialize();
    expect(await storage.accessToken(),'synthetic-existing'); await storage.persistIntent();
    final restarted=AppAuthLogoutPersistence.forProject(url); await restarted.initialize();
    expect(await restarted.accessToken(),isNull);
    final prefs=await SharedPreferences.getInstance(); expect(prefs.getString(key),'synthetic-existing');
    expect(prefs.getString('unrelated'),'keep');
  });
  test('platform removal false cannot masquerade as cache-only success or allow restart restore',() async {
    const url='https://refusing-project.supabase.co'; final key=AppAuthLogoutPersistence.sdkSessionKey(url);
    final originalPlatform=SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    final platform=RefusingSessionRemoval(key,{'flutter.$key':'synthetic-original','flutter.unrelated':'keep'});
    SharedPreferencesStorePlatform.instance=platform;
    try {
      final storage=AppAuthLogoutPersistence.forProject(url); await storage.initialize(); await storage.persistIntent();
      await expectLater(storage.confirmLocalRemoval(),throwsStateError);
      await expectLater(storage.releaseFence(()=>true),throwsStateError);
      expect(storage.blocked,true);
      final disk=await platform.getAll();
      expect(disk['flutter.$key'],'synthetic-original');
      expect(disk['flutter.$key.sko-logout-fence-v1'],'pending-v1');
      SharedPreferences.resetStatic();
      final restart=AppAuthLogoutPersistence.forProject(url); await restart.initialize();
      expect(await restart.hasAccessToken(),false); expect(await restart.accessToken(),isNull);
      expect((await platform.getAll())['flutter.unrelated'],'keep');
    } finally { SharedPreferencesStorePlatform.instance=originalPlatform; SharedPreferences.resetStatic(); }
  });
  test('malformed typed preference is blocked rather than interpreted as absent',() async {
    const url='https://storage-project.supabase.co'; final key=AppAuthLogoutPersistence.sdkSessionKey(url);
    SharedPreferences.setMockInitialValues({key:'synthetic-existing','$key.sko-logout-fence-v1':42});
    final storage=AppAuthLogoutPersistence.forProject(url); await storage.initialize();
    expect(storage.blocked,true); expect(await storage.accessToken(),isNull);
  });
  for(final pending in [false,true]) {
    test('actual SupabaseFlutter initialization and storage callbacks; pending=$pending',() async {
      const url='https://bootstrap-project.supabase.co'; final key=AppAuthLogoutPersistence.sdkSessionKey(url);
      final original=jsonEncode(fixture.session());
      SharedPreferences.setMockInitialValues({key:original,'unrelated':'keep',if(pending)'$key.sko-logout-fence-v1':'pending-v1'});
      final storage=AppAuthLogoutPersistence.forProject(url);
      await Supabase.initialize(url:url,publishableKey:'public-fixture',
        authOptions:FlutterAuthClientOptions(localStorage:storage,autoRefreshToken:false,detectSessionInUri:false),
        httpClient:MockClient((request) async => request.url.path.endsWith('/logout')
          ? http.Response('',204,request:request)
          : http.Response(jsonEncode(fixture.session(sessionId:fixture.nextSid)),200,request:request,headers:{'content-type':'application/json'})));
      try {
        final client=Supabase.instance.client; final gateway=AppAuthMutationGateway.bindPersistence(client,storage);
        expect(client.auth.currentUser?.id,pending?null:fixture.actor);
        expect(gateway.logoutQuarantine.state,pending?AppLogoutQuarantineState.failed:AppLogoutQuarantineState.clear);
        if(!pending) await gateway.signInWithPassword(email:'fixture@example.invalid',password:'synthetic');
        await gateway.signOut();
        expect(client.auth.currentSession,isNull); expect(gateway.logoutQuarantine.state,AppLogoutQuarantineState.clear);
        final prefs=await SharedPreferences.getInstance(); await prefs.reload();
        expect(prefs.containsKey(key),false); expect(prefs.containsKey('$key.sko-logout-fence-v1'),false);
        expect(prefs.getString('unrelated'),'keep');
        final restarted=AppAuthLogoutPersistence.forProject(url); await restarted.initialize();
        expect(await restarted.hasAccessToken(),false);
      } finally { await Supabase.instance.dispose(); }
    });
  }
}
