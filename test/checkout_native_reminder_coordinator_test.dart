import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_native_reminder_bridge.dart';
import 'package:sk_works/features/attendance/checkout_native_reminder_coordinator.dart';

class _Bridge extends CheckoutNativeReminderBridge {
  _Bridge() : super(supported: false);
  final tapEvents = StreamController<String>.broadcast(sync: true);
  final dueEvents = StreamController<String>.broadcast(sync: true);
  final scheduled = <NativeCheckoutDeviceNotification>[];
  final acknowledged = <String>[];
  final cancellations = <bool>[];
  NativeReminderAuthorization permission = NativeReminderAuthorization.authorized;
  NativeReminderScheduleResult scheduleResult = NativeReminderScheduleResult.scheduled;
  String? pending;
  bool supported = true, cancelSucceeds = true;
  int permissionReads = 0, permissionPrompts = 0;
  @override bool get isSupported => supported;
  @override Stream<String> get taps => tapEvents.stream;
  @override Stream<String> get due => dueEvents.stream;
  @override Future<NativeReminderAuthorization> authorizationStatus() async { permissionReads++; return permission; }
  @override Future<NativeReminderAuthorization> requestPermission() async { permissionPrompts++; return permission; }
  @override Future<bool> cancelAll({bool preservePendingTap = false}) async {
    cancellations.add(preservePendingTap);
    if (!preservePendingTap) pending = null;
    return cancelSucceeds;
  }
  @override Future<NativeReminderScheduleResult> schedule({required String sourceId, required DateTime fireAt}) async {
    scheduled.add(NativeCheckoutDeviceNotification(sourceId: sourceId, fireAt: fireAt));
    return scheduleResult;
  }
  @override Future<String?> consumePendingTap() async => pending;
  @override Future<bool> acknowledgePendingTap(String sourceId) async {
    acknowledged.add(sourceId);
    if (pending != sourceId) return false;
    pending = null;
    return true;
  }
  @override Future<void> dispose() async { await tapEvents.close(); await dueEvents.close(); await super.dispose(); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final serverTime = DateTime.utc(2026, 10, 25, 0);
  late _Bridge bridge;
  late StreamController<String?> sessions;
  late CheckoutNativeReminderCoordinator coordinator;
  String? actor, identity;
  late Future<NativeCheckoutDevicePlan> Function() loader;
  late Future<bool> Function(String) checker;
  final checks = <String>[];

  NativeCheckoutDevicePlan plan({String who = 'A', String key = 'A/session-1',
    bool due = false, List<NativeCheckoutDeviceNotification>? notifications}) => NativeCheckoutDevicePlan(
      actorId: who, sessionIdentity: key, serverTime: serverTime,
      hasDueConfirmation: due, notifications: notifications ?? <NativeCheckoutDeviceNotification>[
        NativeCheckoutDeviceNotification(sourceId: '$who:source', fireAt: serverTime.add(const Duration(hours: 8))),
      ],
    );

  CheckoutNativeReminderCoordinator makeCoordinator() => CheckoutNativeReminderCoordinator(
    bridge: bridge, loadPlan: () => loader(), currentActorId: () => actor,
    currentSessionIdentity: () => identity, sessionChanges: sessions.stream,
    requestGateCheck: (source) { checks.add(source); return checker(source); },
  );

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) { await Future<void>.delayed(Duration.zero); }
    expect(done(), true, reason: 'asynchronous work did not reach its expected state');
  }

  setUp(() {
    actor = 'A'; identity = 'A/session-1';
    bridge = _Bridge();
    sessions = StreamController<String?>.broadcast();
    checks.clear();
    loader = () async => plan(who: actor!, key: identity!);
    checker = (_) async => true;
    coordinator = makeCoordinator();
  });
  tearDown(() async { await coordinator.dispose(); await sessions.close(); await bridge.dispose(); });

  test('schedules the exact server instant without client calendar conversion', () async {
    await coordinator.init();
    expect(bridge.scheduled.single.fireAt, DateTime.utc(2026, 10, 25, 8));
    expect(bridge.scheduled.single.sourceId, 'A:source');
    expect(coordinator.status.value, NativeCheckoutSyncStatus.ready);
    expect(bridge.permissionPrompts, 0);
  });
  test('denied permission is truthful while a due foreground check still runs', () async {
    bridge.permission = NativeReminderAuthorization.denied;
    loader = () async => plan(due: true);
    await coordinator.init();
    expect(checks, <String>['']);
    expect(bridge.scheduled, isEmpty);
    expect(coordinator.status.value, NativeCheckoutSyncStatus.permissionDenied);
  });
  test('notDetermined never prompts automatically', () async {
    bridge.permission = NativeReminderAuthorization.notDetermined;
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.permissionRequired);
    expect(bridge.permissionPrompts, 0);
    expect(bridge.scheduled, isEmpty);
  });
  test('quiet authorization remains distinguishable', () async {
    bridge.permission = NativeReminderAuthorization.provisional;
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.ready);
    expect(coordinator.authorization.value, NativeReminderAuthorization.provisional);
  });
  test('unsupported platform invokes no loader or scheduling', () async {
    bridge.supported = false;
    loader = () async => throw StateError('must not read');
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.unsupported);
    expect(bridge.scheduled, isEmpty);
  });
  test('disabled empty plan cancels old reminders without permission work', () async {
    loader = () async => plan(notifications: const []);
    await coordinator.init();
    expect(bridge.cancellations, contains(true));
    expect(coordinator.status.value, NativeCheckoutSyncStatus.inactive);
    expect(bridge.permissionReads, 0);
  });
  test('failed cancellation never schedules another actor plan', () async {
    bridge.cancelSucceeds = false;
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.unavailable);
    expect(bridge.scheduled, isEmpty);
  });
  test('failed plan read preserves cold tap for a later server retry', () async {
    bridge.pending = 'A:source';
    loader = () async => throw StateError('offline');
    await coordinator.init();
    expect(bridge.pending, 'A:source');
    expect(bridge.acknowledged, isEmpty);
    expect(coordinator.status.value, NativeCheckoutSyncStatus.unavailable);
  });
  test('cold tap survives failed validation and clears only after fresh success', () async {
    bridge.pending = 'A:source';
    checker = (_) async => false;
    await coordinator.init();
    expect(bridge.pending, 'A:source');
    expect(bridge.acknowledged, isEmpty);
    checker = (_) async => true;
    await coordinator.refresh();
    expect(bridge.acknowledged, <String>['A:source']);
    expect(bridge.pending, isNull);
  });
  test('live due and tap events request server checks without any clockout write', () async {
    await coordinator.init();
    bridge.dueEvents.add('A:source');
    await until(() => checks.length == 1);
    await Future<void>.delayed(Duration.zero);
    bridge.tapEvents.add('A:source');
    await until(() => checks.length == 2);
    expect(checks, <String>['A:source', 'A:source']);
  });
  test('actor change cancels promptly while the old RPC is still pending', () async {
    final old = Completer<NativeCheckoutDevicePlan>();
    var reads = 0;
    loader = () { reads++; return reads == 1 ? old.future : Future.value(plan(who: 'B', key: 'B/session-2')); };
    final first = coordinator.init();
    await until(() => reads == 1);
    actor = 'B'; identity = 'B/session-2'; sessions.add(identity);
    await until(() => bridge.scheduled.any((v) => v.sourceId == 'B:source'));
    expect(bridge.cancellations, contains(false));
    old.complete(plan());
    await first;
    expect(bridge.scheduled.where((v) => v.sourceId == 'A:source'), isEmpty);
  });
  test('queued A to B to A invalidates old same-current-session response', () async {
    final old = Completer<NativeCheckoutDevicePlan>();
    var reads = 0;
    loader = () { reads++; return reads == 1 ? old.future : Future.value(plan(notifications: const [])); };
    final first = coordinator.init();
    await until(() => reads == 1);
    sessions.add('B/session-2'); sessions.add('A/session-1');
    old.complete(plan());
    await first;
    await until(() => reads >= 2);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.scheduled, isEmpty);
  });
  test('signout cancels device reminders and does not call a signed-out loader', () async {
    await coordinator.init();
    final before = bridge.scheduled.length;
    actor = null; identity = null; sessions.add(null);
    await until(() => coordinator.status.value == NativeCheckoutSyncStatus.inactive);
    expect(bridge.cancellations.last, false);
    expect(bridge.scheduled.length, before);
  });
  test('old failed read cannot replace a newer actor ready status', () async {
    final old = Completer<NativeCheckoutDevicePlan>();
    var reads = 0;
    loader = () { reads++; return reads == 1 ? old.future : Future.value(plan(who: 'B', key: 'B/session-2')); };
    final first = coordinator.init();
    await until(() => reads == 1);
    actor = 'B'; identity = 'B/session-2'; sessions.add(identity);
    await until(() => coordinator.status.value == NativeCheckoutSyncStatus.ready);
    old.completeError(StateError('stale failed request'));
    await first;
    expect(coordinator.status.value, NativeCheckoutSyncStatus.ready);
  });
  test('malformed or duplicate plan sources schedule nothing', () async {
    final item = NativeCheckoutDeviceNotification(sourceId: 'A:source', fireAt: serverTime.add(const Duration(hours: 8)));
    loader = () async => plan(notifications: <NativeCheckoutDeviceNotification>[item, item]);
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.unavailable);
    expect(bridge.scheduled, isEmpty);
  });
  test('partial scheduling failure cancels the partial device plan', () async {
    bridge.scheduleResult = NativeReminderScheduleResult.unavailable;
    await coordinator.init();
    expect(coordinator.status.value, NativeCheckoutSyncStatus.unavailable);
    expect(bridge.cancellations.length, greaterThanOrEqualTo(2));
  });
  test('server cue success after actor flip never acknowledges the old source', () async {
    await coordinator.init();
    final pendingCheck = Completer<bool>();
    checker = (_) => pendingCheck.future;
    bridge.pending = 'A:source'; bridge.tapEvents.add('A:source');
    await until(() => checks.isNotEmpty);
    actor = 'B'; identity = 'B/session-2'; sessions.add(identity);
    await until(() => bridge.cancellations.contains(false));
    pendingCheck.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.acknowledged, isEmpty);
  });
  test('replacement shell is not blocked by old network request or erased by old disposal', () async {
    final old = Completer<NativeCheckoutDevicePlan>();
    loader = () => old.future;
    final first = coordinator.init();
    await Future<void>.delayed(Duration.zero);
    final retired = coordinator;
    await retired.dispose();
    actor = 'B'; identity = 'B/session-2';
    loader = () async => plan(who: 'B', key: 'B/session-2');
    coordinator = makeCoordinator();
    await coordinator.init();
    old.complete(plan());
    await first;
    expect(bridge.scheduled.map((v) => v.sourceId), <String>['B:source']);
    expect(coordinator.status.value, NativeCheckoutSyncStatus.ready);
  });
}
