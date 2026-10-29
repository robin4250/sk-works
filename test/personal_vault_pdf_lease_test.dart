import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/personal_vault/personal_vault_page.dart';
import 'package:sk_works/features/personal_vault/personal_vault_repository.dart';
import 'package:sk_works/features/personal_vault/personal_vault_screen.dart';

const actor = '30000000-0000-0000-0000-000000000001';
const sid = '30000000-0000-0000-0000-000000000002';
const foreign = '30000000-0000-0000-0000-000000000003';
const entry = PersonalVaultEntry(id:'10000000-0000-0000-0000-000000000001:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  label:'本人出勤表', sourceCompanyLabel:'元会社', periodLabel:'保管済み');
final pdf = utf8.encode('%PDF-1.7\nlease fixture');
Map<String, dynamic> session(String sessionId) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'session_id':sessionId,'exp':4102444800})}.fixture',
    'refresh_token':'synthetic-refresh', 'token_type':'bearer', 'expires_in':3600,
    'user':<String,dynamic>{'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
      'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
class Fixture {
  late final SupabaseClient client;
  late final PersonalVaultRepository repository;
  late final http.Client transport;
  Future<void> init() async {
    transport = MockClient((request) async {
      if (request.url.path.contains('/logout')) { return http.Response('{}',200,request:request); }
      if (request.url.path.contains('/storage/')) {
        return http.Response.bytes(pdf,200,headers:{'content-type':'application/pdf'},request:request);
      }
      final data = request.url.path.endsWith('personal_vault24_list_mine') ? <Object>[] : [{
        'object_path':'personal-vault/$actor/${'a'*64}.pdf','object_version':'fixture-version',
        'pdf_hash':sha256.convert(pdf).toString(),'byte_length':pdf.length}];
      return http.Response(jsonEncode(data),200,headers:{'content-type':'application/json'},request:request);
    });
    client = SupabaseClient('https://vault-fixture.invalid','synthetic-public',
      authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:transport);
    await client.auth.setInitialSession(jsonEncode(session(sid)));
    repository = PersonalVaultRepository(client,downloadClientFactory:() => transport);
  }
  Future<void> close() => client.dispose();
}
void main() {
  late Fixture f;
  setUp(() async { f = Fixture(); await f.init(); });
  tearDown(() async { await f.close(); });
  test('operation keeps live history after download and closes retained lazy callbacks on completion', () async {
    late PersonalVaultPdfLease saved;
    await f.repository.withOwnPdf<void>(entry,(lease) async {
      saved = lease;
      final bytes = await lease.readBytes(); expect(bytes,pdf);
      bytes[0] = 0;
      expect(await lease.readBytes(),pdf,reason:'caller cannot mutate held snapshot');
    });
    expect(saved.checkCurrent,throwsStateError);
    await expectLater(saved.readBytes(),throwsStateError);
  });
  test('actual SDK logout after download rejects delayed layout and ends never-settling platform future', () async {
    final ready = Completer<PersonalVaultPdfLease>();
    final native = Completer<void>();
    final pending = f.repository.withOwnPdf<void>(entry,(lease) { ready.complete(lease); return native.future; });
    final failed = expectLater(pending,throwsStateError);
    final lease = await ready.future;
    expect(await lease.readBytes(),pdf);
    await f.client.auth.signOut();
    await failed;
    await expectLater(lease.readBytes(),throwsStateError);
    native.complete();
  });
  test('same UID SID switch and return is terminal after download', () async {
    final ready = Completer<PersonalVaultPdfLease>();
    final native = Completer<void>();
    final pending = f.repository.withOwnPdf<void>(entry,(lease) { ready.complete(lease); return native.future; });
    final failed = expectLater(pending,throwsStateError);
    final lease = await ready.future;
    await f.client.auth.setInitialSession(jsonEncode(session(foreign)));
    await f.client.auth.setInitialSession(jsonEncode(session(sid)));
    await failed;
    await expectLater(lease.readBytes(),throwsStateError);
    native.complete();
  });
  test('lifecycle owner cancellation ends active handoff without waiting for OS', () async {
    final stop = Completer<void>(), native = Completer<void>();
    final ready = Completer<PersonalVaultPdfLease>();
    final pending = f.repository.withOwnPdf<void>(entry,(lease) { ready.complete(lease); return native.future; },invalidated:stop.future);
    final failed = expectLater(pending,throwsStateError);
    final lease = await ready.future; stop.complete();
    await failed;
    await expectLater(lease.readBytes(),throwsStateError);
    native.complete();
  });
  test('cancellation before download does not invoke native handoff', () async {
    var invoked = false;
    await expectLater(f.repository.withOwnPdf<void>(entry,(_) async { invoked = true; },
      invalidated:Future<void>.value()),throwsStateError);
    expect(invoked,isFalse);
  });
  testWidgets('invalidated preview removes only its owned route, preserving a page above it', (tester) async {
    final ready = Completer<PersonalVaultPdfLease>(), native = Completer<void>();
    late Future<void> failed;
    // Start the repository operation in the real zone too: moving only the
    // waiter would leave its session-drain timer trapped in the fake clock.
    final lease = await tester.runAsync(() async {
      final pending = f.repository.withOwnPdf<void>(entry,(lease) { ready.complete(lease); return native.future; });
      failed = expectLater(pending,throwsStateError);
      return ready.future;
    });
    final navigator = GlobalKey<NavigatorState>();
    try {
      await tester.pumpWidget(MaterialApp(navigatorKey:navigator,home:const Text('home')));
      final route = MaterialPageRoute<void>(builder:(_) => PersonalVaultPdfSessionBoundary(
        lease:lease!,child:const Scaffold(body:Text('private PDF'))));
      unawaited(navigator.currentState!.push(route)); await tester.pumpAndSettle();
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder:(_) => const Scaffold(body:Text('unrelated page')))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async { await f.client.auth.signOut(); await failed; });
      await tester.pumpAndSettle();
      expect(route.isActive,isFalse);
      expect(find.text('unrelated page'),findsOneWidget);
      navigator.currentState!.pop(); await tester.pumpAndSettle();
      expect(find.text('private PDF'),findsNothing); expect(find.text('home'),findsOneWidget);
    } finally {
      native.complete();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('background retires existing candidate screen rather than retaining list state', (tester) async {
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(MaterialApp(home:PersonalVaultScreen(client:f.client)));
      await tester.pumpAndSettle();
      expect(find.textContaining('安全のため書類を閉じました'),findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('安全のため書類を閉じました'),findsOneWidget);
    } finally { await tester.pumpWidget(const SizedBox.shrink()); }
  });
  testWidgets('screen created while paused refuses access even after resume', (tester) async {
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(MaterialApp(home:PersonalVaultScreen(client:f.client)));
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('安全のため書類を閉じました'),findsOneWidget);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
