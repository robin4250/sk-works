import 'dart:async';

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
    return const {'secondary_password': true, 'master_feature': false, 'master_security': false};
  }
  @override
  Future<String> requestProof({required String password, required String operation,
      required Map<String, dynamic> target}) async {
    requests++; primary = password; this.operation = operation; this.target = target;
    if (failProof) throw StateError('synthetic denied');
    return pending == null ? 'synthetic-single-use-proof' : await pending!.future;
  }
  @override
  Future<void> replaceSecondaryPassword(String password, String proof) async {
    replacements++; replacement = password;
    expect(proof, 'synthetic-single-use-proof');
    if (failSave) throw StateError('synthetic response lost');
  }
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
    final access = DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
      currentActor: () => 'synthetic-actor');
    await open(tester, access);
    expect(find.byKey(const Key('primary-password')), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(segmented.segments.first.enabled, false);
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
    await open(tester, DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
      currentActor: () => 'synthetic-actor'));
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
    await open(tester, DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
      currentActor: () => 'synthetic-actor'));
    await authenticate(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    expect(transport.replacements, 0);
  });
  testWidgets('background during server verification invalidates the late nonce', (tester) async {
    final transport = _Transport()..pending = Completer<String>();
    final access = DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
      currentActor: () => 'synthetic-actor');
    await open(tester, access);
    await tester.enterText(find.byKey(const Key('primary-password')), 'synthetic-primary');
    await tester.tap(find.text('本人確認する')); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    transport.pending!.complete('synthetic-single-use-proof'); await tester.pumpAndSettle();
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 0);
  });
  testWidgets('ambiguous save clears proof and requires new primary verification', (tester) async {
    final transport = _Transport()..failSave = true;
    final access = DeviceSecondaryPasswordResetAccess(reauthenticationRepository: transport,
      currentActor: () => 'synthetic-actor');
    await open(tester, access);await authenticate(tester);await replacement(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await expectLater(access.save('synthetic-replay'), throwsStateError);
    expect(transport.replacements, 1);
    transport.failSave = false;await authenticate(tester);await replacement(tester);
    expect(transport.requests, 2);expect(transport.replacements, 2);
  });
}
