import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_credential_repository.dart';
import 'package:sk_works/features/settings/master_password_entry_repository.dart';
import 'package:sk_works/features/settings/master_password_protected_page.dart';
import 'package:sk_works/features/settings/master_protected_page.dart';

const _actor = '50000000-0000-0000-0000-000000000001';
const _sid = '50000000-0000-0000-0000-000000000002';
const _binding = MasterCredentialBinding(_actor, _sid, 'synthetic-token-A', 'synthetic-device-key-longer-than-32-characters');
class _Settings implements MasterCredentialAccess { @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation); }
class _Access implements MasterPasswordEntryAccess {
  @override MasterCredentialBinding? binding = _binding;
  final events = StreamController<void>.broadcast(sync: true);
  @override Stream<void> get changes => events.stream;
  @override MasterCredentialAccess get settingsAccess => _Settings();
  bool configured = true, denied = false, faceResult = true;
  int version = 1, reads = 0, faces = 0, begins = 0;
  final passwords = <String>[];
  Completer<bool>? faceWait, verifyWait;
  Completer<MasterCredentialStatus>? readWait;
  @override Future<MasterCredentialStatus> read(MasterCredentialBinding binding) async {
    reads++; if (denied) throw const MasterCredentialRejected('denied');
    return readWait == null ? MasterCredentialStatus(configured: configured, version: version) : readWait!.future;
  }
  @override Future<bool> biometricAvailable() async => true;
  @override Future<bool> biometric() async { faces++; return faceWait == null ? faceResult : faceWait!.future; }
  @override Future<MasterCredentialChallenge> beginUnlock(MasterCredentialBinding binding, int version, String requestId) async {
    begins++; return MasterCredentialChallenge(id: '50000000-0000-0000-0000-000000000003', nonce: 'a' * 64, expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 120)));
  }
  @override Future<void> verifyUnlock(MasterCredentialBinding binding, int version, String requestId, MasterCredentialChallenge challenge, String password) async {
    passwords.add(password);
    final ok = verifyWait == null ? password == 'dedicated-master-password' : await verifyWait!.future;
    if (!ok) throw const MasterCredentialRejected('not_verified');
  }
}
Future<void> _show(WidgetTester t, _Access access, {bool wrapper = false, bool settle = true, Widget Function(MasterCredentialAccess)? settingsBuilder}) async {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final child = const Scaffold(body: Text('MASTER-PRIVATE-CONTENT'));
  await t.pumpWidget(MaterialApp(home: wrapper
    ? MasterProtectedPage(title: 'Master', dedicatedMode: true, dedicatedAccess: access, child: child)
    : MasterPasswordProtectedPage(title: 'Master', access: access, settingsBuilder: settingsBuilder, child: child)));
  if (settle) { await t.pumpAndSettle(); } else { await t.pump(); await t.pump(); }
}
Future<void> _unlock(WidgetTester t, {String password = 'dedicated-master-password', bool settle = true}) async {
  await t.enterText(find.byKey(const Key('master-dedicated-password')), password);
  await t.tap(find.text('Face ID / Touch ID＋Master専用パスワードで開く'));
  if (settle) { await t.pumpAndSettle(); } else { for (var i = 0; i < 5; i++) { await t.pump(); } }
}
Future<void> _close(WidgetTester t, _Access access) async {
  await t.pumpWidget(const SizedBox()); await t.pump(); await access.events.close();
}
void main() {
  testWidgets('explicit candidate wrapper requires actual dedicated password plus Face and server reread', (t) async {
    final access = _Access(); await _show(t, access, wrapper: true); await _unlock(t);
    expect(access.passwords, ['dedicated-master-password']); expect(access.faces, 1);
    expect(access.reads, greaterThanOrEqualTo(3)); expect(find.text('MASTER-PRIVATE-CONTENT'), findsOneWidget);
    await _close(t, access);
  });
  testWidgets('shared secondary password is not a dedicated Master unlock fallback', (t) async {
    final access = _Access(); await _show(t, access); await _unlock(t, password: 'existing-shared-secondary');
    expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); expect(access.passwords, ['existing-shared-secondary']);
    expect(find.textContaining('第2パスワードの代用はできません。'), findsOneWidget); await _close(t, access);
  });
  testWidgets('Face cancel cannot be replaced with dedicated password only', (t) async {
    final access = _Access()..faceResult = false; await _show(t, access); await _unlock(t);
    expect(access.passwords, isEmpty); expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); await _close(t, access);
  });
  testWidgets('unconfigured trusted Master has first setup entry without asking nonexistent dedicated secret', (t) async {
    final access = _Access()..configured = false..version = 0;
    await _show(t, access, settingsBuilder: (_) => Scaffold(body: FilledButton(onPressed: () {}, child: const Text('SYNTHETIC-SETUP'))));
    expect(find.byType(TextField), findsNothing); expect(find.text('Master専用パスワードを初回設定'), findsOneWidget);
    await t.tap(find.text('Master専用パスワードを初回設定')); await t.pumpAndSettle();
    expect(find.text('SYNTHETIC-SETUP'), findsOneWidget); expect(access.faces, 1);
    expect(access.passwords, isEmpty); expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); await _close(t, access);
  });
  testWidgets('setup return never auto unlocks and rereads configured state', (t) async {
    final access = _Access()..configured = false..version = 0;
    await _show(t, access, settingsBuilder: (_) => Builder(builder: (context) => Scaffold(body: FilledButton(onPressed: () { access.configured = true; access.version = 1; Navigator.of(context).pop(true); }, child: const Text('SYNTHETIC-SAVE')))));
    await t.tap(find.text('Master専用パスワードを初回設定')); await t.pumpAndSettle();
    await t.tap(find.text('SYNTHETIC-SAVE')); await t.pumpAndSettle();
    expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); expect(find.byKey(const Key('master-dedicated-password')), findsOneWidget); await _close(t, access);
  });
  testWidgets('denied or unknown server readiness never exposes password/setup forms', (t) async {
    final access = _Access()..denied = true; await _show(t, access);
    expect(find.byType(TextField), findsNothing); expect(find.text('Master専用パスワードを初回設定'), findsNothing);
    expect(access.faces, 0); expect(access.passwords, isEmpty); await _close(t, access);
  });
  testWidgets('Face completion while inactive waits for resumed then verifies captured nonempty dedicated secret', (t) async {
    final access = _Access()..faceWait = Completer<bool>(); await _show(t, access); await _unlock(t, settle: false);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    access.faceWait!.complete(true); await t.pump(); await t.pump(); expect(access.passwords, isEmpty);
    expect(t.widget<TextField>(find.byKey(const Key('master-dedicated-password'))).controller!.text, isEmpty);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    expect(access.passwords, ['dedicated-master-password']); expect(find.text('MASTER-PRIVATE-CONTENT'), findsOneWidget); await _close(t, access);
  });
  testWidgets('real background invalidates Face and never sends captured password afterward', (t) async {
    final access = _Access()..faceWait = Completer<bool>(); await _show(t, access); await _unlock(t, settle: false);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) { t.binding.handleAppLifecycleStateChanged(state); }
    access.faceWait!.complete(true); await t.pumpAndSettle();
    expect(access.passwords, isEmpty); expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); await _close(t, access);
  });
  testWidgets('actor replacement rejects late verified reply and locks without touching another session', (t) async {
    final access = _Access()..verifyWait = Completer<bool>(); await _show(t, access); await _unlock(t, settle: false);
    access.binding = const MasterCredentialBinding('other-actor', _sid, 'synthetic-B', 'other-device-key-longer-than-32-characters'); access.events.add(null);
    access.verifyWait!.complete(true); await t.pumpAndSettle();
    expect(find.text('MASTER-PRIVATE-CONTENT'), findsNothing); expect(find.byType(TextField), findsNothing); await _close(t, access);
  });
  testWidgets('load interrupted by inactive offers reload and can recover', (t) async {
    final access = _Access()..readWait = Completer<MasterCredentialStatus>(); await _show(t, access, settle: false);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    access.readWait!.complete(const MasterCredentialStatus(configured: true, version: 1));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing); expect(find.text('再読み込み'), findsOneWidget);
    access.readWait = null; await t.tap(find.text('再読み込み')); await t.pumpAndSettle(); await _unlock(t);
    expect(find.text('MASTER-PRIVATE-CONTENT'), findsOneWidget); await _close(t, access);
  });
}
