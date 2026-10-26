import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/apple_account_link.dart';
import 'package:sk_works/features/auth/apple_account_link_card.dart';

const actor = '20000000-0000-0000-0000-000000000001';
const other = '20000000-0000-0000-0000-000000000002';
Map<String, dynamic> user(String id, {bool apple = false, bool google = true}) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': {'provider': 'google'},
  'identities': [for (final p in [if (google) 'google', if (apple) 'apple'])
    {'id': '$id-$p', 'identity_id': id, 'user_id': id, 'provider': p,
      'identity_data': {'sub': id}, 'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z'}],
};
String session(String id, {int age = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({'access_token': '${part({})}.${part({'sub':id,'exp':now+3600,
      'amr':[{'method':'oauth','timestamp':now-age}]})}.synthetic',
    'refresh_token':'synthetic', 'token_type':'bearer', 'expires_in':3600,
    'user':user(id)});
}

class RealHttpOverrides extends HttpOverrides {}

class MemoryPKCE extends GotrueAsyncStorage {
  final values = <String, String>{};
  Completer<void>? hold;
  Completer<void>? reached;
  @override Future<String?> getItem({required String key}) async => values[key];
  @override Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
    reached?.complete();
    await hold?.future;
  }
  @override Future<void> removeItem({required String key}) async { values.remove(key); }
}

// These three widget tests isolate dialog/session invalidation. Their readiness
// is deterministic; real preflight reads are covered in the dedicated source
// tests. begin(), auth events, original client and security guards stay real.
class WidgetReadinessAppleLink extends AppleAccountLink {
  WidgetReadinessAppleLink(super.client, {
    required Future<bool> Function() providerCheck,
    required Future<bool> Function(Uri) launch,
  }) : super.forTesting(
    settingsUrl: Uri.parse('https://apple-link.invalid/auth/v1/settings'),
    publicKey: 'public-synthetic', providerCheck: providerCheck, launch: launch);

  @override Future<AppleLinkReadiness> readiness() async =>
      await providerEnabled() ? AppleLinkReadiness.ready : AppleLinkReadiness.providerDisabled;
}

class EventAppleLink extends AppleAccountLink {
  EventAppleLink(super.client, this.events, {required Future<bool> Function(Uri) launch})
      : super.forTesting(settingsUrl: Uri.parse('https://apple-link.invalid/auth/v1/settings'),
          publicKey: 'public-synthetic', providerCheck: () async => true, launch: launch);
  final Stream<AuthState> events;
  @override Stream<AuthState> get changes => events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AppleAccountLink source;
  late MockClient network;
  late List<String> paths;
  late MemoryPKCE pkce;
  late bool enabled, apple, google;
  late int launches;
  String role = 'owner';
  String responseActor = actor;
  String authorizeUrl = 'https://appleid.apple.com/auth/authorize?synthetic=true';
  Completer<void>? holdAuthorize;
  Completer<void>? gotAuthorize;
  Completer<void>? holdProvider, gotProvider;
  setUp(() async {
    paths=[]; enabled=true; apple=false; google=true; launches=0; role='owner';
    responseActor=actor; holdAuthorize=null; gotAuthorize=null;
    holdProvider=null; gotProvider=null;
    authorizeUrl='https://appleid.apple.com/auth/authorize?synthetic=true';
    network=MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/logout')) return http.Response('{}',200,headers:{'content-type':'application/json'},request:request);
      if (request.url.path.endsWith('/settings')) {
        return http.Response(jsonEncode({'external':{'apple':enabled}}),200,headers:{'content-type':'application/json'},request:request);
      }
      if (request.url.path.endsWith('/user/identities/authorize')) {
        gotAuthorize?.complete();
        await holdAuthorize?.future;
        return http.Response(jsonEncode({'url':authorizeUrl}),200,headers:{'content-type':'application/json'},request:request);
      }
      if (request.url.path.endsWith('/user')) {
        return http.Response(jsonEncode(user(responseActor,apple:apple,google:google)),200,headers:{'content-type':'application/json'},request:request);
      }
      if (request.url.path.endsWith('/company_members')) {
        return http.Response(jsonEncode([{'company_id':'synthetic-company','role':role}]),200,headers:{'content-type':'application/json'},request:request);
      }
      throw StateError('Unexpected HTTP request');
    });
    pkce=MemoryPKCE();
    client=SupabaseClient('https://apple-link.invalid','public-synthetic',
      authOptions:AuthClientOptions(autoRefreshToken:false,
        authFlowType:AuthFlowType.pkce,pkceAsyncStorage:pkce), httpClient:network);
    await client.auth.setInitialSession(session(actor));
    source=AppleAccountLink.forTesting(client,
      settingsUrl:Uri.parse('https://apple-link.invalid/auth/v1/settings'),
      publicKey:'public-synthetic',providerCheck:() async {
        gotProvider?.complete(); await holdProvider?.future; return enabled; },
      launch:(uri) async { launches++; return true; });
  });
  tearDown(() async { await source.dispose(); await client.dispose(); });

  AppleAccountLink widgetSource() {
    final value = WidgetReadinessAppleLink(client, providerCheck: () async => enabled,
      launch: (uri) async { launches++; return true; });
    addTearDown(value.dispose);
    return value;
  }

  test('actual settings HTTP accepts enabled JSON and rejects oversized chunked body',() async {
    var oversized=false;
    final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    addTearDown(() => server.close(force:true));
    server.listen((request) async {
      try {
        request.response.headers.chunkedTransferEncoding=true;
        request.response.write('{"external":{"apple":true}}');
        if (oversized) request.response.add(List<int>.filled(65537,32));
        await request.response.close();
      } catch (_) { /* Client deliberately aborts an oversized stream. */ }
    });
    final liveSettings=AppleAccountLink(client,
      settingsUrl:Uri.parse('http://127.0.0.1:${server.port}/settings'),publicKey:'public-synthetic');
    addTearDown(liveSettings.dispose);
    Future<bool> read() => HttpOverrides.runZoned(liveSettings.providerEnabled,
      createHttpClient:(context)=>RealHttpOverrides().createHttpClient(context));
    expect(await read(),true);
    oversized=true;
    expect(await read(),false);
    expect(launches,0);
  });
  test('provider disabled prevents authorize or browser launch',() async {
    enabled=false;
    await expectLater(source.begin(),throwsStateError);
    expect(launches,0);
    expect(paths, isNot(contains('GET /auth/v1/user/identities/authorize')));
  });
  test('same UID adds Apple, preserves Google, verifies existing membership',() async {
    await source.begin();
    expect(launches,1); expect(source.pending,true);
    expect(await source.verifyCompletion(),false);
    apple=true;
    expect(await source.verifyCompletion(),true);
    expect(client.auth.currentUser!.id,actor);
    expect(paths,contains('GET /auth/v1/user/identities/authorize'));
    expect(paths.any((p)=>p.contains('/signup')||p.contains('/token')||
      p=='GET /auth/v1/authorize'||p.startsWith('POST')),false);
  });
  test('stale OAuth requires recent login without starting Apple',() async {
    await client.auth.setInitialSession(session(actor,age:301));
    await expectLater(source.begin(),throwsStateError); expect(launches,0);
  });
  test('another server user or missing Google cannot start linking',() async {
    responseActor=other;
    await expectLater(source.begin(),throwsStateError); expect(launches,0);
    responseActor=actor; google=false;
    await expectLater(source.begin(),throwsStateError); expect(launches,0);
  });
  test('changed UID while SDK authorize awaits never launches response',() async {
    holdAuthorize=Completer<void>(); gotAuthorize=Completer<void>();
    final operation=source.begin();
    final rejected=expectLater(operation,throwsStateError);
    await gotAuthorize!.future;
    await client.auth.setInitialSession(session(other));
    holdAuthorize!.complete(); await rejected; expect(launches,0);
  });
  test('UID changes during SDK PKCE storage cannot open a different account URL',() async {
    pkce.hold=Completer<void>(); pkce.reached=Completer<void>();
    final operation=source.begin();
    final rejected=expectLater(operation,throwsStateError);
    await pkce.reached!.future;
    await client.auth.setInitialSession(session(other));
    pkce.hold!.complete(); await rejected;
    expect(launches,0);
  });
  test('same-UID logout then login never resurrects old authorize URL',() async {
    holdAuthorize=Completer<void>(); gotAuthorize=Completer<void>();
    final operation=source.begin();
    final rejected=expectLater(operation,throwsStateError);
    await gotAuthorize!.future;
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);
    await client.auth.setInitialSession(session(actor));
    holdAuthorize!.complete(); await rejected; expect(launches,0);
  });
  test('same actor token replacement during provider read blocks Apple authorization',() async {
    holdProvider=Completer<void>(); gotProvider=Completer<void>();
    final operation=source.begin();
    final rejected=expectLater(operation,throwsA(isA<StateError>()
      .having((e)=>e.message,'reason','apple_link_session_changed')));
    await gotProvider!.future;
    await client.auth.setInitialSession(session(actor,age:1));
    final replacement=client.auth.currentSession!.accessToken;
    holdProvider!.complete(); await rejected;
    expect(launches,0); expect(source.pending,false);
    expect(paths,isNot(contains('GET /auth/v1/user/identities/authorize')));
    expect(client.auth.currentSession!.accessToken,replacement);
    expect(paths.any((p)=>p.startsWith('POST')),false);
  });
  test('same actor token replacement during authorize never opens old Apple URL',() async {
    holdAuthorize=Completer<void>(); gotAuthorize=Completer<void>();
    final operation=source.begin();
    final rejected=expectLater(operation,throwsA(isA<StateError>()
      .having((e)=>e.message,'reason','apple_link_session_changed')));
    await gotAuthorize!.future;
    await client.auth.setInitialSession(session(actor,age:1));
    final replacement=client.auth.currentSession!.accessToken;
    holdAuthorize!.complete(); await rejected;
    expect(launches,0); expect(source.pending,false);
    expect(client.auth.currentSession!.accessToken,replacement);
    expect(paths.any((p)=>p.startsWith('POST')),false);
  });
  test('historical other-actor event refuses old Apple URL after current actor returns',() async {
    final events=StreamController<AuthState>();
    final value=EventAppleLink(client,events.stream,
      launch:(uri) async {launches++;return true;});
    addTearDown(events.close); addTearDown(value.dispose);
    holdAuthorize=Completer<void>(); gotAuthorize=Completer<void>();
    final operation=value.begin();
    final rejected=expectLater(operation,throwsA(isA<StateError>()
      .having((e)=>e.message,'reason','apple_link_session_changed')));
    await gotAuthorize!.future;
    final original=client.auth.currentSession!;
    // Current session is already A while the queued historical B event arrives.
    events.add(AuthState(AuthChangeEvent.signedIn,
      Session.fromJson(jsonDecode(session(other)) as Map<String,dynamic>)));
    events.add(AuthState(AuthChangeEvent.signedIn,original));
    await Future<void>.delayed(Duration.zero);
    holdAuthorize!.complete(); await rejected;
    expect(launches,0);expect(value.pending,false);
    expect(client.auth.currentSession!.accessToken,original.accessToken);
  });
  test('same-account token update after Apple handoff can complete normally',() async {
    await source.begin();
    await client.auth.setInitialSession(session(actor,age:1));
    await Future<void>.delayed(Duration.zero);
    apple=true;
    expect(await source.verifyCompletion(),true);
    expect(launches,1);expect(client.auth.currentUser!.id,actor);
    expect(paths.any((p)=>p.startsWith('POST')),false);
  });
  test('untrusted authorization host cannot receive a browser launch',() async {
    authorizeUrl='https://example.invalid/steal';
    await expectLater(source.begin(),throwsStateError); expect(launches,0);
  });
  test('Google identity disappearing cannot report completion',() async {
    await source.begin(); apple=true; google=false;
    await expectLater(source.verifyCompletion(),throwsStateError);
  });
  test('company role change after Apple consent cannot report completion',() async {
    await source.begin(); apple=true; role='worker';
    await expectLater(source.verifyCompletion(),throwsStateError);
  });
  test('logout after browser launch stops completion instead of waiting forever',() async {
    await source.begin();
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);
    await expectLater(source.verifyCompletion(),throwsStateError);
  });
  test('canceled old URL cannot revive when a new operation starts',() async {
    holdAuthorize=Completer<void>(); gotAuthorize=Completer<void>();
    final first=source.begin(); final rejected=expectLater(first,throwsStateError);
    await gotAuthorize!.future;
    final oldHold=holdAuthorize!;
    await source.cancel();
    holdAuthorize=null; gotAuthorize=null;
    await source.begin();
    expect(launches,1);
    oldHold.complete(); await rejected;
    expect(launches,1); expect(source.pending,true);
  });
  testWidgets('dialog for A closes when another UID signs in without linking B',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:AppleAccountLinkCard(source:widgetSource()))));
    await t.pumpAndSettle();
    await t.tap(find.text('このアカウントにAppleを追加'));
    await t.pumpAndSettle();
    expect(find.text('Appleの本人確認へ'),findsOneWidget);
    await client.auth.setInitialSession(session(other));
    await t.pumpAndSettle();
    expect(find.text('Appleの本人確認へ'),findsNothing);
    expect(launches,0);
    expect(paths, isNot(contains('GET /auth/v1/user/identities/authorize')));
  });
  testWidgets('dialog for A cannot survive same-UID logout and login ABA',(t) async {
    await t.pumpWidget(MaterialApp(home:Scaffold(body:AppleAccountLinkCard(source:widgetSource()))));
    await t.pumpAndSettle();
    await t.tap(find.text('このアカウントにAppleを追加'));
    await t.pumpAndSettle();
    expect(find.text('Appleの本人確認へ'),findsOneWidget);
    await client.auth.signOut(scope:SignOutScope.local);
    await client.auth.setInitialSession(session(actor));
    await t.pumpAndSettle();
    expect(find.text('Appleの本人確認へ'),findsNothing);
    expect(launches,0);
    expect(paths, isNot(contains('GET /auth/v1/user/identities/authorize')));
  });
  testWidgets('disabled provider retains preparation text without active button',(t) async {
    enabled=false;
    await t.pumpWidget(MaterialApp(home:Scaffold(body:AppleAccountLinkCard(source:widgetSource()))));
    await t.pumpAndSettle();
    expect(find.textContaining('Apple連携は提供準備中'),findsOneWidget);
    expect(find.text('このアカウントにAppleを追加'),findsNothing);
    expect(launches,0);
  });
}
