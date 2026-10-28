import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shifts/own_published_shift_repository.dart';

const _actor = '10000000-0000-4000-8000-000000000001';
const _other = '10000000-0000-4000-8000-000000000002';
const _company = '10000000-0000-4000-8000-000000000003';
Map<String, dynamic> _session(String actor, String marker) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'exp':4102444800})}.$marker',
    'refresh_token':'synthetic-refresh','token_type':'bearer','expires_in':3600,
    'user':<String,dynamic>{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
      'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late StreamController<AuthState> changes;
  late List<OwnPublishedShiftRepository> repositories;
  late List<String> paths;
  Future<void> Function(String)? beforeResponse;
  setUp(() async {
    paths = []; repositories = []; beforeResponse = null;
    changes = StreamController<AuthState>.broadcast();
    client = SupabaseClient('https://shift-fixture.invalid','synthetic-public',
      authOptions:const AuthClientOptions(autoRefreshToken:false),
      httpClient:MockClient((request) async {
        paths.add(request.url.path);
        await beforeResponse?.call(request.url.path);
        final value = request.url.path.endsWith('company_members')
          ? [<String,dynamic>{'company_id':_company}]
          : request.url.path.endsWith('sites')
            ? [<String,dynamic>{'id':'site','name':'本人現場'}] : [];
        return http.Response(jsonEncode(value),200,
          headers:{'content-type':'application/json'},request:request);
      }));
    await client.auth.setInitialSession(jsonEncode(_session(_actor,'original')));
  });
  tearDown(() async {
    for (final repository in repositories) { repository.dispose(); }
    await changes.close(); await client.dispose();
  });
  OwnPublishedShiftRepository repository({bool realStream=false}) {
    final value = OwnPublishedShiftRepository(client,authChanges:realStream ? null : changes.stream);
    repositories.add(value); return value;
  }
  void history(String actor,String marker) {
    changes.add(AuthState(AuthChangeEvent.signedIn,Session.fromJson(_session(actor,marker))));
    changes.add(AuthState(AuthChangeEvent.signedIn,client.auth.currentSession));
  }
  test('actual pinned SDK initialSession replay permits the normal first own read',() async {
    final value = await repository(realStream:true).loadContext();
    expect(value.companyId,_company); expect(value.siteNames,{'site':'本人現場'});
    expect(await value.gateway.listMonth(_company,DateTime(2026,10)),isEmpty);
    expect(paths,hasLength(3)); expect(ownShiftEntryReleased,isFalse);
  });
  test('queued foreign actor return rejects before any company read',() async {
    final value = repository(); history(_other,'foreign');
    await expectLater(value.loadContext(),throwsStateError); expect(paths,isEmpty);
  });
  test('same UID token switch and return rejects pending company response',() async {
    final value = repository();
    beforeResponse = (path) async { if (path.endsWith('company_members')) { history(_actor,'replaced'); } };
    await expectLater(value.loadContext(),throwsStateError);
    expect(paths,hasLength(1)); expect(paths.single,endsWith('company_members'));
  });
  test('same-current initial replay does not erase later historical actor changes',() async {
    final value = repository();
    changes.add(AuthState(AuthChangeEvent.initialSession,client.auth.currentSession));
    history(_other,'foreign');
    await expectLater(value.loadContext(),throwsStateError); expect(paths,isEmpty);
  });
  test('Auth stream error is handled and terminal before further reads or RPC',() async {
    final value = repository(); final context = await value.loadContext(); paths.clear();
    changes.addError(StateError('synthetic offline refresh'));
    await expectLater(value.loadContext(),throwsStateError);
    await expectLater(context.gateway.listMonth(_company,DateTime(2026,10)),throwsStateError);
    expect(paths,isEmpty);
    changes.add(AuthState(AuthChangeEvent.signedIn,client.auth.currentSession));
    await expectLater(value.loadContext(),throwsStateError); expect(paths,isEmpty);
  });
  test('Auth stream completion is terminal without an RPC or unhandled error',() async {
    final value = repository(); final context = await value.loadContext(); paths.clear();
    await changes.close();
    await expectLater(value.loadContext(),throwsStateError);
    await expectLater(context.gateway.listMonth(_company,DateTime(2026,10)),throwsStateError);
    expect(paths,isEmpty);
  });
  test('dispose rejects pending read before publishing a usable context',() async {
    final value = repository(); final started=Completer<void>(),released=Completer<void>();
    beforeResponse = (path) async {
      if (path.endsWith('company_members')) { started.complete(); await released.future; }
    };
    final pending=value.loadContext(); await started.future;
    value.dispose(); released.complete();
    await expectLater(pending,throwsStateError); expect(paths,hasLength(1));
  });
  test('queued token history during shift RPC rejects a late successful response',() async {
    final context=await repository().loadContext(); paths.clear();
    beforeResponse = (path) async { if (path.contains('/rpc/')) { history(_actor,'replaced'); } };
    await expectLater(context.gateway.listMonth(_company,DateTime(2026,10)),throwsStateError);
    expect(paths,hasLength(1));
  });
}
