import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/operation_reauthentication_repository.dart';
import 'package:sk_works/features/chat/line_import_feature_settings_panel.dart';
import 'package:sk_works/features/settings/master_feature_controls_page.dart';
import 'package:sk_works/features/settings/master_feature_controls_repository.dart';
import 'package:sk_works/features/settings/master_feature_proof_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actorA = '10000000-0000-0000-0000-000000000001';
const actorB = '10000000-0000-0000-0000-000000000002';
final nonce = 'a' * 64;
Map<String, dynamic> flags() => {for (final key in MasterFeatureControlsRepository.supportedFeatures) key: true,
 'trade_documents_master_contract_version':1};
class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused fixture SDK');
}
class _Proofs extends OperationReauthenticationRepository {
  _Proofs() : super(_UnusedClient());
  int calls = 0;
  bool fail = false;
  Completer<String>? pending;
  Map<String, dynamic>? target;
  @override
  Future<String> requestProof({required String password, required String operation,
      required Map<String, dynamic> target, String? captchaToken}) async {
    calls++;
    expectSync(password, 'synthetic-primary');
    expectSync(operation, 'master.feature.set');
    this.target = target;
    if (fail) throw StateError('synthetic private failure');
    return pending == null ? nonce : await pending!.future;
  }
}
class _Features implements MasterFeatureControlsRepository {
  String? currentActor = actorA;
  bool required = true;
  bool capFailure = false;
  bool writeFailure = false;
  int loads = 0;
  int caps = 0;
  final changes = <Map<String, dynamic>>[];
  final values = flags();
  Completer<bool>? pendingCapability;
  Completer<MasterFeatureAvailability>? pendingWrite;
  @override
  String? get actorId => currentActor;
  @override
  Future<MasterFeatureAvailability> load() async { loads++; return MasterFeatureAvailability.fromJson(values); }
  @override
  Future<bool> reauthenticationRequired() async {
    caps++;
    if (capFailure) throw StateError('synthetic private failure');
    return pendingCapability == null ? required : await pendingCapability!.future;
  }
  @override
  Future<MasterFeatureAvailability> setEnabled({required String featureKey, required bool enabled,
      String? proof, String? expectedActor}) async {
    expectSync(expectedActor, actorA);
    changes.add({'feature_key': featureKey, 'enabled': enabled, 'proof': proof});
    if (writeFailure) throw StateError('synthetic private failure');
    if (pendingWrite != null) return pendingWrite!.future;
    values[featureKey] = enabled;
    return MasterFeatureAvailability.fromJson(values);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected feature method');
}
// A confirmation intentionally leaves a busy progress indicator on the page
// beneath a non-opaque dialog. Assertions wait for finite route animations,
// never for that intentionally non-settling indicator or a pending response.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}
Future<void> _open(WidgetTester tester, _Features repository, _Proofs proofs) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: MasterFeatureControlsPage(repository: repository, reauthentication: proofs)));
  await _frames(tester);
}
Future<void> _confirm(WidgetTester tester, {bool enabling = false}) async {
  await tester.tap(find.widgetWithText(SwitchListTile, '車両管理'));
  await _frames(tester);
  await tester.tap(find.widgetWithText(FilledButton, enabling ? '有効にする' : '一時停止する'));
  // Some cases intentionally keep capability/write futures pending. Advance
  // route animation without waiting for their visible progress indicator.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}
Future<void> _verify(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('master-feature-password')), 'synthetic-primary');
  await tester.tap(find.text('本人確認して変更'));
  await _frames(tester);
  await tester.pump();
  await _frames(tester);
}
String token(String actor) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': '20000000-0000-0000-0000-000000000001', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
}
class _Wire {
  _Wire() {
    client = SupabaseClient('https://feature-fixture.invalid', 'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        final response = await handle(request);
        return http.Response.bytes(response.bodyBytes, response.statusCode,
          headers: response.headers, request: request);
      }));
    repository = MasterFeatureControlsRepository.forTesting(client);
  }
  late final SupabaseClient client;
  late final MasterFeatureControlsRepository repository;
  String actor = actorA;
  int capStatus = 200;
  int writeStatus = 200;
  bool capNetwork = false;
  Object cap = {'protocol': 'sko-reauthentication-v1', 'secondary_password': false,
    'master_feature': true, 'master_security': false};
  Future<void> Function()? duringCap;
  Future<void> Function()? duringWrite;
  final calls = <http.Request>[];
  Iterable<http.Request> get writes => calls.where((r) => r.url.path.contains('/set_master_feature_enabled'));
  Future<void> login() => client.auth.signInWithPassword(phone: '+810000000000', password: 'synthetic').then((_) {});
  http.Response json(Object? value, [int status = 200]) => http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/auth/v1/token') {
      return json({'access_token': token(actor), 'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': actor, 'aud': 'authenticated', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-16T00:00:00Z'}});
    }
    if (request.url.path.endsWith('/reauthentication_capabilities')) {
      if (capNetwork) throw StateError('synthetic network');
      await duringCap?.call();
      return json(cap, capStatus);
    }
    if (request.url.path.contains('/set_master_feature_enabled')) {
      await duringWrite?.call();
      final payload=jsonDecode(request.body) as Map;
      return writeStatus == 200 ? json({...flags(),payload['p_feature_key'] as String:payload['p_enabled']}) : json({'code': 'PGRST202', 'message': 'synthetic missing'}, writeStatus);
    }
    throw StateError('Unexpected fixture endpoint');
  }
}
void main() {
  testWidgets('ON preserves confirmation and requires proof for the exact feature and next value', (tester) async {
    final f = _Features(), p = _Proofs();
    await _open(tester, f, p);
    expect(find.text('Master 機能設定'), findsOneWidget);
    expect(find.text('LINE追加機能'), findsOneWidget);
    expect(find.textContaining('既存データや履歴は削除しません'), findsNothing);
    await _confirm(tester);
    expect(f.changes, isEmpty);
    expect(find.text('機能を一時停止する'), findsOneWidget);
    await _verify(tester);
    expect(f.changes.single, {'feature_key': 'vehicle_management', 'enabled': false, 'proof': nonce});
    expect(p.target, {'feature_key': 'vehicle_management', 'enabled': false});
    await _confirm(tester, enabling: true);
    await _verify(tester);
    expect(f.changes.last['enabled'], true);
    expect(p.target, {'feature_key': 'vehicle_management', 'enabled': true});
    expect(find.text('LINE追加機能'), findsOneWidget);
  });
  testWidgets('OFF preserves the legacy confirmation and no password prompt', (tester) async {
    final f = _Features()..required = false;
    final p = _Proofs();
    await _open(tester, f, p);
    await _confirm(tester);
    expect(f.changes.single['proof'], null);
    expect(p.calls, 0);
    expect(find.byKey(const Key('master-feature-password')), findsNothing);
  });
  testWidgets('cancel, capability error, proof error and failed save never downgrade or retry writes', (tester) async {
    final f = _Features(), p = _Proofs();
    await _open(tester, f, p);
    await tester.tap(find.widgetWithText(SwitchListTile, '車両管理'));
    await _frames(tester);
    await tester.tap(find.text('戻る'));
    await _frames(tester);
    expect(f.caps, 0);
    f.capFailure = true;
    await _confirm(tester);
    expect(f.changes, isEmpty);
    expect(p.calls, 0);
    expect(find.textContaining('synthetic private'), findsNothing);
    f.capFailure = false;
    await _confirm(tester);
    await tester.tap(find.text('キャンセル'));
    await _frames(tester);
    expect(f.changes, isEmpty);
    p.fail = true;
    await _confirm(tester);
    await _verify(tester);
    expect(f.changes, isEmpty);
    await tester.tap(find.text('キャンセル'));
    await _frames(tester);
    p.fail = false;
    f.writeFailure = true;
    await _confirm(tester);
    await _verify(tester);
    expect(f.changes.length, 1);
    expect(f.changes.single['proof'], nonce);
  });
  testWidgets('stale duplicate callback opens only one confirmation and proof', (tester) async {
    final f = _Features(), p = _Proofs();
    await _open(tester, f, p);
    final callback = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '車両管理')).onChanged!;
    callback(false);
    callback(false);
    await _frames(tester);
    expect(find.text('車両管理を一時停止する'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '一時停止する'));
    await _frames(tester);
    await _verify(tester);
    expect(p.calls, 1);
    expect(f.changes.length, 1);
  });
  testWidgets('actor change during capability never opens proof or writes', (tester) async {
    final pending = Completer<bool>();
    final f = _Features()..pendingCapability = pending;
    final p = _Proofs();
    await _open(tester, f, p);
    await _confirm(tester);
    f.currentActor = actorB;
    pending.complete(true);
    await _frames(tester);
    expect(f.changes, isEmpty);
    expect(p.calls, 0);
    expect(find.byKey(const Key('master-feature-password')), findsNothing);
  });
  testWidgets('background cancels confirmation and pending proof; resume needs fresh confirmation and proof', (tester) async {
    final f = _Features(), p = _Proofs();
    await _open(tester, f, p);
    final existingPanelState = tester.state(find.byType(LineImportFeatureSettingsPanel));
    await tester.tap(find.widgetWithText(SwitchListTile, '車両管理'));
    await _frames(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(find.text('車両管理を一時停止する'), findsNothing);
    expect(identical(tester.state(find.byType(LineImportFeatureSettingsPanel)), existingPanelState), true);
    expect(f.caps, 0);
    p.pending = Completer<String>();
    await _confirm(tester);
    await tester.enterText(find.byKey(const Key('master-feature-password')), 'synthetic-primary');
    await tester.tap(find.text('本人確認して変更'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('master-feature-password'))).controller!.text, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(find.byKey(const Key('master-feature-password')), findsNothing);
    p.pending!.complete(nonce);
    await _frames(tester);
    expect(f.changes, isEmpty);
    p.pending = null;
    await _confirm(tester);
    await _verify(tester);
    expect(p.calls, 2);
    expect(f.changes.length, 1);
    expect(find.text('LINE追加機能'), findsOneWidget);
  });
  testWidgets('late save result after background cannot replace freshly loaded flags', (tester) async {
    final pending = Completer<MasterFeatureAvailability>();
    final f = _Features()..required = false..pendingWrite = pending;
    final p = _Proofs();
    await _open(tester, f, p);
    await _confirm(tester);
    expect(f.changes.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(f.loads, 2);
    pending.complete(const MasterFeatureAvailability(vehicleManagement: false, routeAssignment: false));
    await _frames(tester);
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '車両管理')).value, true);
  });
  for (final interrupt in ['actor', 'background']) {
    testWidgets('post-proof frame rejects $interrupt change', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      String? actor = actorA;
      final pending = Completer<String>();
      var returned = 0;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
        onPressed: () async {
          final proof = await showDialog<String>(context: context, builder: (_) => MasterFeatureProofDialog(
            expectedActor: actorA, currentActor: () => actor, label: '車両管理', enabled: false,
            requestProof: (_) => pending.future));
          if (proof != null) returned++;
        }, child: const Text('open')))));
      await tester.tap(find.text('open'));
      await _frames(tester);
      await tester.enterText(find.byKey(const Key('master-feature-password')), 'synthetic-primary');
      await tester.tap(find.text('本人確認して変更'));
      pending.complete(nonce);
      await tester.idle();
      if (interrupt == 'actor') { actor = actorB; }
      else { tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); }
      await _frames(tester);
      expect(returned, 0);
      expect(find.byKey(const Key('master-feature-password')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }
  test('SDK only explicit OFF/missing capability preserves legacy, all other failures deny', () async {
    final f = _Wire(); addTearDown(f.client.dispose); await f.login();
    expect(await f.repository.reauthenticationRequired(), true);
    f.cap = {'protocol': 'sko-reauthentication-v1', 'secondary_password': false, 'master_feature': false, 'master_security': false};
    expect(await f.repository.reauthenticationRequired(), false);
    f.capStatus = 404; f.cap = {'code': 'PGRST202', 'message': 'synthetic missing'};
    expect(await f.repository.reauthenticationRequired(), false);
    f.capStatus = 403; f.cap = {'code': '42501', 'message': 'synthetic denied'};
    await expectLater(f.repository.reauthenticationRequired(), throwsA(isA<PostgrestException>()));
    f.capStatus = 200; f.cap = {'protocol': 'sko-reauthentication-v1', 'master_feature': true};
    await expectLater(f.repository.reauthenticationRequired(), throwsStateError);
    f.capNetwork = true;
    await expectLater(f.repository.reauthenticationRequired(), throwsA(anything));
    expect(f.writes, isEmpty);
  });
  test('SDK supported features and both values carry bound bearer and nonce without a fallback', () async {
    final f = _Wire(); addTearDown(f.client.dispose); await f.login();
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    for (final key in MasterFeatureControlsRepository.supportedFeatures) {
      for (final enabled in [false, true]) {
        await f.repository.setEnabled(featureKey: key, enabled: enabled, proof: nonce, expectedActor: actorA);
        final write = f.writes.last;
        expect(write.url.path.endsWith('/set_master_feature_enabled_with_proof'), true);
        expect(write.headers['authorization'], bearer);
        expect(jsonDecode(write.body), {'p_feature_key': key, 'p_enabled': enabled, 'p_proof': nonce});
      }
    }
    await f.repository.setEnabled(featureKey: 'vehicle_management', enabled: false, expectedActor: actorA);
    expect(f.writes.last.url.path.endsWith('/set_master_feature_enabled'), true);
    final before = f.writes.length;
    await expectLater(f.repository.setEnabled(featureKey:'site_order_documents',enabled:true),throwsStateError);
    expect(f.writes.length,before);
    f.writeStatus = 404;
    await expectLater(f.repository.setEnabled(featureKey: 'vehicle_management', enabled: false, proof: nonce), throwsA(isA<PostgrestException>()));
    expect(f.writes.length, before + 1);
    expect(f.writes.last.url.path.endsWith('_with_proof'), true);
  });
  test('SDK invalid target/proof or foreign expected actor never sends a write', () async {
    final f = _Wire(); addTearDown(f.client.dispose); await f.login();
    await expectLater(f.repository.setEnabled(featureKey: 'line', enabled: true, proof: nonce), throwsArgumentError);
    await expectLater(f.repository.setEnabled(featureKey: 'vehicle_management', enabled: true, proof: ''), throwsArgumentError);
    await expectLater(f.repository.setEnabled(featureKey: 'vehicle_management', enabled: true, expectedActor: actorB), throwsStateError);
    expect(f.writes, isEmpty);
  });
  test('SDK actor switch rejects capability and late write result while preserving original wire actor', () async {
    final f = _Wire(); addTearDown(f.client.dispose); await f.login();
    f.duringCap = () async { f.actor = actorB; await f.login(); };
    await expectLater(f.repository.reauthenticationRequired(), throwsStateError);
    f.duringCap = null; f.actor = actorA; await f.login();
    final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
    f.duringWrite = () async { f.actor = actorB; await f.login(); };
    await expectLater(f.repository.setEnabled(featureKey: 'vehicle_management', enabled: false, proof: nonce, expectedActor: actorA), throwsStateError);
    expect(f.writes.single.headers['authorization'], bearer);
  });
}
