import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/operation_reauthentication_repository.dart';
import 'package:sk_works/features/settings/master_device_management_page.dart';
import 'package:sk_works/features/settings/master_device_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const deviceId = '40000000-0000-0000-0000-000000000001';
class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused SDK in widget fixture');
}
class _Proofs extends OperationReauthenticationRepository {
  _Proofs() : super(_UnusedClient());
  int requests = 0;
  bool fail = false;
  Completer<String>? pending;
  Map<String, dynamic>? target;
  @override
  Future<String> requestProof({required String password, required String operation,
      required Map<String, dynamic> target}) async {
    requests++;expect(operation, 'master.device.lock');expect(password, 'synthetic-primary');
    this.target = target;if (fail) throw StateError('synthetic denied');
    return pending == null ? 'synthetic-single-use-proof' : await pending!.future;
  }
}
class _Devices implements MasterDeviceRepository {
  String? currentActor = actor;
  bool required = true;
  bool failCapability = false;
  bool locked = false;
  int capabilityCalls = 0;
  int changes = 0;
  String? proof;
  @override
  String? get currentUserId => currentActor;
  @override
  Future<bool> isMasterAdmin() async => true;
  @override
  Future<List<MasterDeviceRecord>> loadDevices() async => [MasterDeviceRecord(
    id: deviceId, deviceName: 'synthetic device', deviceType: 'iphone',
    registeredAt: DateTime(2026, 10, 16), isLocked: locked)];
  @override
  Future<bool> lockReauthenticationRequired() async {
    capabilityCalls++;if (failCapability) throw StateError('synthetic permission error');return required;
  }
  @override
  Future<void> setLocked({required String deviceId, required bool locked, String? proof}) async {
    expect(deviceId, masterDeviceId);changes++;this.locked = locked;this.proof = proof;
  }
  static const masterDeviceId = deviceId;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected device method');
}
Future<void> _open(WidgetTester tester, _Devices devices, _Proofs proofs) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(home: MasterDeviceManagementPage(repository: devices, reauthentication: proofs)));
  await tester.pumpAndSettle();
}
Future<void> lock(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'ロック'));await tester.pumpAndSettle();
}
Future<void> verify(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('master-device-lock-password')), 'synthetic-primary');
  await tester.tap(find.text('本人確認して変更'));await tester.pumpAndSettle();
  await tester.pump();await tester.pumpAndSettle();
}
void main() {
  testWidgets('ON requires primary proof, binds exact device/value and completes lock then unlock', (tester) async {
    final devices = _Devices(),proofs = _Proofs();await _open(tester, devices, proofs);
    await lock(tester);expect(devices.changes, 0);await verify(tester);
    expect(devices.changes, 1);expect(devices.proof, 'synthetic-single-use-proof');
    expect(proofs.target, {'device_id': deviceId, 'locked': true});
    await tester.tap(find.widgetWithText(OutlinedButton, 'ロック解除'));await tester.pumpAndSettle();await verify(tester);
    expect(devices.changes, 2);expect(devices.locked, false);
    expect(proofs.target, {'device_id': deviceId, 'locked': false});
  });
  testWidgets('OFF preserves existing device flow without credentials', (tester) async {
    final devices = _Devices()..required = false;final proofs = _Proofs();await _open(tester, devices, proofs);
    await lock(tester);expect(devices.changes, 1);expect(devices.proof, null);expect(proofs.requests, 0);
  });
  testWidgets('capability error and cancelled or denied proof never call a legacy setter', (tester) async {
    final devices = _Devices()..failCapability = true;final proofs = _Proofs();await _open(tester, devices, proofs);
    await lock(tester);expect(devices.changes, 0);expect(proofs.requests, 0);
    devices.failCapability = false;await lock(tester);await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();
    expect(devices.changes, 0);proofs.fail = true;await lock(tester);await verify(tester);
    expect(devices.changes, 0);expect(find.textContaining('本パスワードで本人確認できませんでした'), findsOneWidget);
  });
  testWidgets('actor switch and background invalidate late proofs', (tester) async {
    final devices = _Devices(),proofs = _Proofs()..pending = Completer<String>();await _open(tester, devices, proofs);
    await lock(tester);await tester.enterText(find.byKey(const Key('master-device-lock-password')), 'synthetic-primary');
    await tester.tap(find.text('本人確認して変更'));await tester.pump();
    devices.currentActor = '10000000-0000-0000-0000-000000000002';
    proofs.pending!.complete('synthetic-single-use-proof');await tester.pumpAndSettle();expect(devices.changes, 0);
    await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();
    devices.currentActor = actor;proofs.pending = Completer<String>();await lock(tester);
    await tester.enterText(find.byKey(const Key('master-device-lock-password')), 'synthetic-primary');
    await tester.tap(find.text('本人確認して変更'));await tester.pump();
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    proofs.pending!.complete('synthetic-single-use-proof');await tester.pumpAndSettle();expect(devices.changes, 0);
  });
  testWidgets('stale duplicate lock callback cannot open duplicate proof requests', (tester) async {
    final devices = _Devices(),proofs = _Proofs();await _open(tester, devices, proofs);
    final callback = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'ロック')).onPressed!;
    final pendingChange = (callback as dynamic)() as Future<void>;
    callback();await tester.pumpAndSettle();expect(devices.capabilityCalls, 1);
    await verify(tester);expect(proofs.requests, 1);
    expect(find.byKey(const Key('master-device-lock-password')), findsNothing);
    await pendingChange;
    expect(devices.changes, 1);
  });
  test('SDK only missing capability downgrades; new proof setter carries exact nonce', () async {
    int status = 200;Object result = {'protocol': 'sko-master-device-lock-v1', 'enabled': true};
    final calls = <http.Request>[];
    final client = SupabaseClient('https://fixture.invalid', 'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {calls.add(request);return http.Response(
        jsonEncode(request.url.path.endsWith('master_device_lock_capability') ? result : null),
        request.url.path.endsWith('master_device_lock_capability') ? status : 200,
        headers: {'content-type': 'application/json'}, request: request);}));
    addTearDown(client.dispose);final repository = MasterDeviceRepository.forTesting(client);
    expect(await repository.lockReauthenticationRequired(), true);
    status = 404;result = {'code': 'PGRST202', 'message': 'synthetic missing'};
    expect(await repository.lockReauthenticationRequired(), false);
    status = 403;result = {'code': '42501', 'message': 'synthetic denied'};
    await expectLater(repository.lockReauthenticationRequired(), throwsA(isA<PostgrestException>()));
    await repository.setLocked(deviceId: deviceId, locked: true, proof: 'synthetic-proof');
    expect(calls.last.url.path.endsWith('set_master_device_locked_with_proof'), true);
    expect(jsonDecode(calls.last.body), {'p_device_id': deviceId, 'p_locked': true, 'p_proof': 'synthetic-proof'});
    await repository.setLocked(deviceId: deviceId, locked: false);
    expect(calls.last.url.path.endsWith('/set_master_device_locked'), true);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
