import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/operation_reauthentication_repository.dart';
import 'package:sk_works/features/auth/secondary_password_reset_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Tests the actual device access class and widget without an Auth service or
// native biometric prompt. Only the operation transport is replaced.
class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('The widget fixture must use the injected operation transport');
}
class _Transport extends OperationReauthenticationRepository {
  _Transport() : super(_UnusedClient());
  int requests = 0;
  int replacements = 0;
  int capabilityCalls = 0;
  bool failCapability = false;
  bool changeSupported = false;
  bool recoverySupported = true;
  bool enabled = true;
  int changes = 0;
  bool failProof = false;
  bool failSave = false;
  Completer<String>? pending;
  String? operation;
  Map<String, dynamic>? target;
  String? primary;
  String? replacement;
  @override
  Future<Map<String, bool>> capabilities() async {
    capabilityCalls++;
    if (failCapability) throw StateError('synthetic unavailable');
    return {'secondary_password': enabled, 'master_feature': false, 'master_security': false,
      'secondary_password_change_supported': changeSupported,
      'secondary_password_recovery_supported': recoverySupported};
  }
  @override
  Future<String> requestProof({required String password, required String operation,
      required Map<String, dynamic> target, String? captchaToken}) async {
    requests++; primary = password; this.operation = operation; this.target = target;
    if (failProof) throw StateError('synthetic denied');
    return pending == null ? 'synthetic-single-use-proof' : await pending!.future;
  }
  @override
  Future<void> changeSecondaryPassword(String password, String proof) async {
    changes++;
    await replaceSecondaryPassword(password, proof);
  }
  @override
  Future<void> replaceSecondaryPassword(String password, String proof) async {
    replacements++; replacement = password;
    expect(proof, 'synthetic-single-use-proof');
    if (failSave) throw StateError('synthetic response lost');
  }
}
class _SessionFixture {
  final events = StreamController<AuthState>.broadcast();
  final int expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  late Session? current = session('synthetic-actor', 'original-session');
  Session session(String actor, String sid, {int? expiry}) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return Session.fromJson({'access_token': '${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':expiry ?? expiresAt})}.synthetic',
      'refresh_token':'synthetic-only', 'token_type':'bearer', 'expires_in':3600,
      'user': {'id':actor,'aud':'authenticated','role':'authenticated',
        'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{},'created_at':'2026-10-01T00:00:00Z'}})!;
  }
  void change(String actor, String sid, {int? expiry}) {
    current = session(actor, sid, expiry: expiry);
    events.add(AuthState(AuthChangeEvent.signedIn, current));
  }
}
DeviceSecondaryPasswordResetAccess _accessFor(_Transport transport, {_SessionFixture? session}) {
  final fixture = session ?? _SessionFixture();
  addTearDown(fixture.events.close);
  return DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
    currentActor: () => fixture.current?.user.id, currentSession: () => fixture.current,
    authChanges: fixture.events.stream);
}

Future<void> open(WidgetTester tester, DeviceSecondaryPasswordResetAccess access) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: TextButton(onPressed: () async {
      final completed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SecondaryPasswordResetPage(access: access)));
      if (completed == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('completed')));
      }
    }, child: const Text('open'))))));
  await tester.tap(find.text('open')); await tester.pumpAndSettle();
}
Future<void> authenticate(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('primary-password')), 'synthetic-primary');
  await tester.tap(find.text('本人確認する')); await tester.pumpAndSettle();
}
Future<void> replacement(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('reset-password')), 'synthetic-replacement');
  await tester.enterText(find.byKey(const Key('reset-confirm')), 'synthetic-replacement');
  await tester.tap(find.text('再設定する')); await tester.pumpAndSettle();
}
void main() {
  testWidgets('enabled device flow requires server primary proof and completes with proof RPC', (tester) async {
    final transport = _Transport();
    final access = _accessFor(transport);
    await open(tester, access);
    expect(find.byKey(const Key('primary-password')), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await authenticate(tester); await replacement(tester);
    expect(transport.requests, 1); expect(transport.replacements, 1);
    expect(transport.operation, 'secondary_password.replace');
    expect(transport.target, {'user_id': 'synthetic-actor'});
    expect(transport.primary, 'synthetic-primary');
    expect(transport.replacement, 'synthetic-replacement');
    expect(find.text('completed'), findsOneWidget);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 1);
  });
  testWidgets('capability failure cannot downgrade to biometric or legacy reset', (tester) async {
    final transport = _Transport()..failCapability = true;
    await open(tester, _accessFor(transport));
    expect(find.textContaining('本人確認の設定を確認できませんでした'), findsOneWidget);
    await tester.tap(find.text('本人確認する')); await tester.pump();
    expect(transport.requests, 0);expect(transport.replacements, 0);
    transport.failCapability = false;
    await tester.tap(find.text('再読み込み')); await tester.pumpAndSettle();
    await authenticate(tester); await replacement(tester);
    expect(transport.replacements, 1);
  });
  testWidgets('denied proof keeps replacement form hidden and sends no save', (tester) async {
    final transport = _Transport()..failProof = true;
    await open(tester, _accessFor(transport));
    await authenticate(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    expect(transport.replacements, 0);
  });
  testWidgets('background during server verification invalidates the late nonce', (tester) async {
    final transport = _Transport()..pending = Completer<String>();
    final access = _accessFor(transport);
    await open(tester, access);
    await tester.enterText(find.byKey(const Key('primary-password')), 'synthetic-primary');
    await tester.tap(find.text('本人確認する')); await tester.pump();
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden,
        AppLifecycleState.paused, AppLifecycleState.hidden,
        AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    transport.pending!.complete('synthetic-single-use-proof'); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 0);
  });
  testWidgets('ambiguous save clears proof and requires new primary verification', (tester) async {
    final transport = _Transport()..failSave = true;
    final access = _accessFor(transport);
    await open(tester, access);await authenticate(tester);await replacement(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 1);
    transport.failSave = false;await authenticate(tester);await replacement(tester);
    expect(transport.requests, 2);expect(transport.replacements, 2);
  });
  test('queued A-B-A during proof request cannot authorize a later save', () async {
    final transport = _Transport()..pending = Completer<String>();
    final fixture = _SessionFixture();final access = _accessFor(transport, session: fixture);
    await access.loadRequirement();
    final pending = expectLater(access.authenticateWithPassword('synthetic-primary'), throwsStateError);
    fixture.change('other', 'other-session');
    fixture.change('synthetic-actor', 'original-session');
    transport.pending!.complete('synthetic-single-use-proof');
    await pending;
    await expectLater(access.save('synthetic-replacement'), throwsStateError);
    expect(transport.replacements, 0);
  });
  for (final mode in ['A-B-A', 'same-actor-new-session', 'signed-out-event']) {
    test('verification cannot survive auth history before save: $mode', () async {
      final transport = _Transport();final fixture = _SessionFixture();
      final access = _accessFor(transport, session: fixture);
      await access.loadRequirement();expect(await access.authenticateWithPassword('synthetic-primary'), isTrue);
      if (mode == 'A-B-A') fixture.change('other', 'other-session');
      if (mode == 'signed-out-event') fixture.events.add(AuthState(AuthChangeEvent.signedOut, null));
      fixture.change('synthetic-actor', mode == 'same-actor-new-session' ? 'new-session' : 'original-session');
      await expectLater(access.save('synthetic-replacement'), throwsStateError);
      expect(transport.replacements, 0);
      expect(fixture.current!.user.id, 'synthetic-actor');
    });
  }
  test('same-session JWT refresh retains one valid reset attempt', () async {
    final transport = _Transport();final fixture = _SessionFixture();
    final access = _accessFor(transport, session: fixture);
    await access.loadRequirement();expect(await access.authenticateWithPassword('synthetic-primary'), isTrue);
    final token = fixture.current!.accessToken;
    fixture.change('synthetic-actor', 'original-session', expiry: fixture.expiresAt + 60);
    expect(fixture.current!.accessToken, isNot(token));
    await access.save('synthetic-replacement');
    expect(transport.replacements, 1);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 1);
  });
  testWidgets('restored actor after queued session switch hides the verified form', (tester) async {
    final transport = _Transport();final fixture = _SessionFixture();
    final access = _accessFor(transport, session: fixture);
    await open(tester, access);await authenticate(tester);
    expect(find.byKey(const Key('reset-password')), findsOneWidget);
    fixture.change('other', 'other-session');fixture.change('synthetic-actor', 'original-session');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reset-password')), findsNothing);
    expect(find.text('ログイン状態が変わりました。本人確認をやり直してください。'), findsOneWidget);
    expect(transport.replacements, 0);
  });

  testWidgets('known secondary change works while Google-only forgotten recovery is preparing', (tester) async {
    final transport = _Transport()..changeSupported = true..recoverySupported = false;
    await open(tester, _accessFor(transport));
    expect(find.text('現在の第2パスワード'), findsOneWidget);
    await tester.tap(find.text('第2パスワードを忘れた場合'));await tester.pumpAndSettle();
    expect(find.textContaining('第2パスワードを忘れた場合の再設定は準備中'), findsOneWidget);
    await authenticate(tester);await replacement(tester);
    expect(transport.operation, 'secondary_password.change');expect(transport.changes, 1);
  });
  testWidgets('server OFF never offers native reset or legacy bearer fallback', (tester) async {
    final transport = _Transport()..enabled = false;
    final access = _accessFor(transport);
    await open(tester, access);
    expect(find.textContaining('第2パスワードの再設定は準備中'), findsOneWidget);
    expect(find.byKey(const Key('primary-password')), findsNothing);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await expectLater(access.authenticateWithPassword('synthetic-primary'), throwsStateError);
    await expectLater(access.save('synthetic-replacement'), throwsStateError);
    expect(transport.requests, 0);expect(transport.replacements, 0);
  });

}

