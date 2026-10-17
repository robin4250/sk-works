import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_credential_repository.dart';
import 'package:sk_works/features/settings/master_credential_setup_page.dart';

const _binding = MasterCredentialBinding('actor-A', 'session-A', 'token-A', 'synthetic-device-key-longer-than-32');
class _Access implements MasterCredentialAccess {
  @override MasterCredentialBinding? binding = _binding;
  final events = StreamController<void>.broadcast(sync: true);
  @override Stream<void> get changes => events.stream;
  bool configured = false, denied = false, unknown = false, found = false, terminal = false;
  int begins = 0, commits = 0, receipts = 0;
  String? operation, verification, password;
  MasterCredentialPending? journal;
  Completer<void>? commitWait;
  Completer<void>? rememberWait;
  Completer<MasterCredentialStatus>? loadWait;
  Completer<MasterCredentialChallenge>? beginWait;
  @override Future<MasterCredentialStatus> read(MasterCredentialBinding binding) async { if (denied) throw const MasterCredentialRejected('denied'); if (loadWait != null) return loadWait!.future; return MasterCredentialStatus(configured: configured, version: configured ? 3 : 0); }
  @override Future<MasterCredentialChallenge> begin(MasterCredentialBinding binding, MasterCredentialPending pending) async { begins++; operation = pending.operation; if (beginWait != null) return beginWait!.future; return challenge(); }
  MasterCredentialChallenge challenge() => MasterCredentialChallenge(id: 'challenge', nonce: 'synthetic-in-memory', expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 120)));
  @override Future<void> commit(MasterCredentialBinding binding, MasterCredentialPending pending, MasterCredentialChallenge challenge, {required String verificationPassword, required String newPassword}) async { commits++; verification = verificationPassword; password = newPassword; if (commitWait != null) await commitWait!.future; if (unknown) throw StateError('synthetic unknown'); }
  @override Future<MasterCredentialReceipt> receipt(MasterCredentialBinding binding, MasterCredentialPending pending) async { receipts++; return terminal ? MasterCredentialReceipt.notApplied : found ? MasterCredentialReceipt.applied : MasterCredentialReceipt.pending; }
  @override Future<MasterCredentialPending?> pending(MasterCredentialBinding binding) async => journal;
  @override Future<void> remember(MasterCredentialPending pending) async { journal = pending; if (rememberWait != null) await rememberWait!.future; }
  @override Future<void> forget(MasterCredentialPending pending) async { if (journal?.requestId == pending.requestId) journal = null; }
}
Future<void> _show(WidgetTester t, _Access access, {GlobalKey<NavigatorState>? navigation, bool settle = true}) async {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  addTearDown(access.events.close);
  await t.pumpWidget(MaterialApp(navigatorKey: navigation, home: MasterCredentialSetupPage(access: access)));
  if (settle) { await t.pumpAndSettle(); } else { await t.pump(); }
}
Future<void> _fill(WidgetTester t, {String confirm = 'new-master-password'}) async {
  await t.enterText(find.byType(TextField).at(0), 'existing-secret');
  await t.enterText(find.byType(TextField).at(1), 'new-master-password');
  await t.enterText(find.byType(TextField).at(2), confirm);
}
void main() {
  testWidgets('server status is required before any password form is visible', (t) async {
    final access = _Access()..loadWait = Completer<MasterCredentialStatus>();
    await _show(t, access, settle: false); expect(find.byType(TextField), findsNothing);
    access.loadWait!.complete(const MasterCredentialStatus(configured: false, version: 0)); await t.pumpAndSettle();
    expect(find.text('現在の第2パスワード（初回本人確認）'), findsOneWidget);
  });
  testWidgets('denied or unavailable server exposes no form and changes no credentials', (t) async {
    final access = _Access()..denied = true; await _show(t, access);
    expect(find.byType(TextField), findsNothing); expect(access.commits, 0);
    expect(find.text('再読み込み'), findsOneWidget);
  });
  testWidgets('initial setup passes existing secondary secret and gives explicit completion', (t) async {
    final access = _Access(); await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); await t.pumpAndSettle();
    expect(access.operation, 'setup'); expect(access.verification, 'existing-secret');
    expect(access.password, 'new-master-password'); expect(access.commits, 1);
    expect(access.journal, isNull); expect(find.byType(TextField), findsNothing);
    expect(find.text('Master専用パスワードの保存が完了しました。'), findsOneWidget);
  });
  testWidgets('change uses current dedicated Master password label and change operation', (t) async {
    final access = _Access()..configured = true; await _show(t, access);
    expect(find.text('現在のMaster専用パスワード'), findsOneWidget); await _fill(t);
    await t.tap(find.text('変更して保存')); await t.pumpAndSettle(); expect(access.operation, 'change');
  });
  testWidgets('confirmation mismatch sends no challenge or mutation', (t) async {
    final access = _Access(); await _show(t, access); await _fill(t, confirm: 'different');
    await t.tap(find.text('初回登録して保存')); await t.pumpAndSettle(); expect(access.begins, 0); expect(access.commits, 0);
  });
  testWidgets('UTF16 pairs do not bypass the eight-codepoint password minimum', (t) async {
    final access = _Access(); await _show(t, access);
    await t.enterText(find.byType(TextField).at(0), 'existing-secret');
    await t.enterText(find.byType(TextField).at(1), '😀😀😀😀');
    await t.enterText(find.byType(TextField).at(2), '😀😀😀😀');
    await t.tap(find.text('初回登録して保存')); await t.pumpAndSettle();
    expect(access.begins, 0); expect(access.commits, 0);
  });
  testWidgets('help explains setup and change without exposing or retaining input', (t) async {
    final access = _Access(); await _show(t, access); await _fill(t);
    await t.tap(find.byTooltip('ヘルプ')); await t.pumpAndSettle();
    expect(find.text('Master専用パスワードについて'), findsOneWidget);
    expect(find.textContaining('現在の第2パスワードで本人確認'), findsOneWidget);
    expect(find.textContaining('現在のMaster専用パスワードで確認'), findsOneWidget);
    expect(find.textContaining('通信結果が不明な場合は再送せず'), findsOneWidget);
    expect(find.text('existing-secret'), findsNothing); expect(find.text('new-master-password'), findsNothing);
    await t.tap(find.text('閉じる')); await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); expect(find.text('再読み込み'), findsOneWidget);
    expect(access.begins, 0); expect(access.commits, 0);
    await t.tap(find.text('再読み込み')); await t.pumpAndSettle();
    for (final field in t.widgetList<TextField>(find.byType(TextField))) { expect(field.controller!.text, isEmpty); }
  });
  testWidgets('background clears secrets and rejects late challenge', (t) async {
    final access = _Access()..beginWait = Completer<MasterCredentialChallenge>(); await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); await t.pump();
    expect(t.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'ヘルプ')).onPressed, isNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    access.beginWait!.complete(access.challenge()); await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); expect(access.commits, 0); expect(access.journal, isNull);
  });
  testWidgets('route cover clears form without requiring OS background', (t) async {
    final access = _Access(); final navigation = GlobalKey<NavigatorState>(); await _show(t, access, navigation: navigation); await _fill(t);
    navigation.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('covered')))); await t.pumpAndSettle();
    navigation.currentState!.pop(); await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); expect(access.commits, 0);
  });
  testWidgets('actor or token change clears fields and prevents stale status admission', (t) async {
    final access = _Access(); await _show(t, access); await _fill(t);
    access.binding = const MasterCredentialBinding('actor-B', 'session-B', 'token-B', 'synthetic-device-key-longer-than-32'); access.events.add(null); await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); expect(access.commits, 0);
  });
  testWidgets('late successful commit cannot show completion to another actor', (t) async {
    final access = _Access()..commitWait = Completer<void>(); await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); for (var i = 0; i < 5; i++) { await t.pump(); }
    expect(access.commits, 1);
    access.binding = const MasterCredentialBinding('actor-B', 'session-B', 'token-B', 'synthetic-device-key-longer-than-32'); access.events.add(null);
    access.commitWait!.complete(); await t.pumpAndSettle();
    expect(find.text('Master専用パスワードの保存が完了しました。'), findsNothing); expect(find.byType(TextField), findsNothing);
  });
  testWidgets('stale attempt cleanup cannot erase a newer challenge', (t) async {
    final oldChallenge = Completer<MasterCredentialChallenge>();
    final access = _Access()..beginWait = oldChallenge; await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); await t.pump();
    expect(t.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == 'ヘルプ')).onPressed, isNull);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    access.beginWait = null;
    await t.tap(find.text('再読み込み')); await t.pumpAndSettle(); await _fill(t);
    access.rememberWait = Completer<void>();
    await t.tap(find.text('初回登録して保存')); for (var i = 0; i < 5; i++) { await t.pump(); }
    oldChallenge.complete(access.challenge()); for (var i = 0; i < 5; i++) { await t.pump(); }
    access.rememberWait!.complete(); await t.pumpAndSettle();
    expect(access.commits, 1); expect(find.text('Master専用パスワードの保存が完了しました。'), findsOneWidget);
  });
  testWidgets('explicit terminal not_applied clears pending without claiming success or resending', (t) async {
    final access = _Access()..unknown = true; await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); await t.pumpAndSettle();
    access.terminal = true; await t.tap(find.text('保存結果を照合')); await t.pumpAndSettle();
    expect(access.commits, 1); expect(access.journal, isNull);
    expect(find.text('Master専用パスワードの保存が完了しました。'), findsNothing);
    expect(find.textContaining('保存されていないことを確認しました'), findsOneWidget);
    expect(find.text('再読み込み'), findsOneWidget);
  });
  testWidgets('unknown result never resends and not_found receipt remains pending', (t) async {
    final access = _Access()..unknown = true; await _show(t, access); await _fill(t);
    await t.tap(find.text('初回登録して保存')); await t.pumpAndSettle();
    expect(access.commits, 1); expect(access.journal, isNotNull); expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('保存結果を照合')); await t.pumpAndSettle();
    expect(access.commits, 1); expect(access.receipts, 1); expect(access.journal, isNotNull);
    access.found = true; await t.tap(find.text('保存結果を照合')); await t.pumpAndSettle();
    expect(access.commits, 1); expect(access.journal, isNull);
    expect(find.text('Master専用パスワードの保存が完了しました。'), findsOneWidget);
  });
}
