import 'dart:async';

import 'package:flutter/foundation.dart';

import 'checkout_native_reminder_bridge.dart';

@immutable
class NativeCheckoutDeviceNotification {
  const NativeCheckoutDeviceNotification({required this.sourceId, required this.fireAt});
  final String sourceId;
  /// A concrete server-generated instant, never a client timezone calculation.
  final DateTime fireAt;
}

@immutable
class NativeCheckoutDevicePlan {
  const NativeCheckoutDevicePlan({required this.actorId, required this.sessionIdentity,
    required this.serverTime, required this.notifications, required this.hasDueConfirmation});
  final String actorId, sessionIdentity;
  final DateTime serverTime;
  final List<NativeCheckoutDeviceNotification> notifications;
  final bool hasDueConfirmation;
}

enum NativeCheckoutSyncStatus { idle, ready, inactive, unsupported, permissionRequired, permissionDenied, unavailable, disposed }

/// Keeps OS reminders synchronized with a server-authorized plan.
///
/// The repository adapter must return concrete UTC fire instants and a plan
/// checked against its current actor/session. Emitted session identities must
/// retain event.session's UID/SID, not map every event to the current SDK value.
/// No time arithmetic, clockout, report save, signature or navigation occurs here.
class CheckoutNativeReminderCoordinator {
  CheckoutNativeReminderCoordinator({
    required Future<NativeCheckoutDevicePlan> Function() loadPlan,
    required String? Function() currentActorId,
    required String? Function() currentSessionIdentity,
    required Stream<String?> sessionChanges,
    required Future<bool> Function(String sourceId) requestGateCheck,
    CheckoutNativeReminderBridge? bridge,
  }) : _loadPlan = loadPlan, _actor = currentActorId, _session = currentSessionIdentity,
       _events = sessionChanges, _requestGateCheck = requestGateCheck,
       _bridge = bridge ?? CheckoutNativeReminderBridge.instance;

  final Future<NativeCheckoutDevicePlan> Function() _loadPlan;
  final String? Function() _actor, _session;
  final Stream<String?> _events;
  /// True only after a fresh actor-scoped server read verifies the cue (or
  /// identifies it as stale). A signal-only local refresh must not return true.
  final Future<bool> Function(String sourceId) _requestGateCheck;
  final CheckoutNativeReminderBridge _bridge;
  final _status = ValueNotifier(NativeCheckoutSyncStatus.idle);
  final _authorization = ValueNotifier(NativeReminderAuthorization.unknown);
  ValueListenable<NativeCheckoutSyncStatus> get status => _status;
  ValueListenable<NativeReminderAuthorization> get authorization => _authorization;
  StreamSubscription<String?>? _sessionSubscription;
  StreamSubscription<String>? _tapSubscription, _dueSubscription;
  String? _observedSession;
  bool _initialized = false, _disposed = false;
  int _generation = 0;
  final _checkingCues = <String>{};

  // One bridge owns one device queue, including when a new authenticated shell
  // replaces the old coordinator while its permission/plan request is pending.
  static Future<void> _deviceQueue = Future<void>.value();
  static CheckoutNativeReminderCoordinator? _owner;

  /// Saved settings/clockout hooks can refresh the authenticated shell's plan.
  /// Never invoke from the gate read callback itself.
  static Future<void> refreshCurrent() async {
    final owner = _owner;
    if (owner != null) await owner.refresh();
  }

  Future<void> _serial(Future<void> Function() action) {
    final task = _deviceQueue.then((_) => action());
    _deviceQueue = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  bool _current(int generation, String? actor, String? session) =>
      !_disposed && identical(_owner, this) && _generation == generation &&
      _actor() == actor && _session() == session;

  void _setStatus(NativeCheckoutSyncStatus value) {
    if (!_disposed && identical(_owner, this)) _status.value = value;
  }

  Future<void> init() async {
    if (_disposed) return;
    if (_initialized) return refresh();
    _initialized = true;
    _owner = this;
    _observedSession = _session();
    _sessionSubscription = _events.listen((emitted) {
      if (_disposed || !identical(_owner, this) || emitted == _observedSession) return;
      _observedSession = emitted;
      // Invalidate in-flight work immediately, including queued A→B→A events.
      _generation++;
      unawaited(_clearForSessionChange());
    }, onError: (Object _) {
      if (!_disposed && identical(_owner, this)) {
        _generation++;
        _setStatus(NativeCheckoutSyncStatus.unavailable);
        unawaited(_clearForSessionChange());
      }
    });
    _tapSubscription = _bridge.taps.listen((source) => unawaited(_handleCue(source)));
    _dueSubscription = _bridge.due.listen((source) => unawaited(_handleCue(source)));
    await refresh();
  }

  Future<void> _clearForSessionChange() async {
    try {
      if (_disposed || !identical(_owner, this)) return;
      await _bridge.cancelAll();
      if (!_disposed && identical(_owner, this)) await refresh();
    } catch (_) {
      _setStatus(NativeCheckoutSyncStatus.unavailable);
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (!_initialized) return init();
    final generation = ++_generation;
    final actor = _actor(), session = _session();
    if (!_current(generation, actor, session)) return;
    if (!_bridge.isSupported) { _setStatus(NativeCheckoutSyncStatus.unsupported); return; }
    try {
      // Clear stale schedules promptly, but preserve cold-start evidence during
      // same-actor refresh. Account changes use the stronger default cancellation.
      final cancelled = await _bridge.cancelAll(preservePendingTap: actor != null && session != null);
      if (!_current(generation, actor, session)) return;
      if (!cancelled) { _setStatus(NativeCheckoutSyncStatus.unavailable); return; }
      if (actor == null || session == null) { _setStatus(NativeCheckoutSyncStatus.inactive); return; }
      // Never hold the native device queue during a network operation. A slow
      // old actor RPC cannot delay logout cancellation or the new actor's plan.
      final plan = await _loadPlan();
      await Future<void>.delayed(Duration.zero);
      if (!_current(generation, actor, session)) return;
      if (plan.actorId != actor || plan.sessionIdentity != session || !plan.serverTime.isUtc || plan.notifications.length > 32) {
        _setStatus(NativeCheckoutSyncStatus.unavailable); return;
      }
      final sources = <String>{};
      for (final item in plan.notifications) {
        if (!CheckoutNativeReminderBridge.validSourceId(item.sourceId) || !sources.add(item.sourceId) ||
            !item.fireAt.isUtc || !item.fireAt.isAfter(plan.serverTime) ||
            item.fireAt.difference(plan.serverTime) >= const Duration(days: 8)) {
          _setStatus(NativeCheckoutSyncStatus.unavailable); return;
        }
      }
      if (plan.hasDueConfirmation) await _handleCue('');
      if (!_current(generation, actor, session)) return;
      await _serial(() async {
        if (!_current(generation, actor, session)) return;
        if (plan.notifications.isEmpty && !plan.hasDueConfirmation) { _setStatus(NativeCheckoutSyncStatus.inactive); return; }
        final permission = await _bridge.authorizationStatus();
        if (!_current(generation, actor, session)) return;
        _authorization.value = permission;
        if (permission == NativeReminderAuthorization.denied) { _setStatus(NativeCheckoutSyncStatus.permissionDenied); return; }
        if (permission == NativeReminderAuthorization.notDetermined) { _setStatus(NativeCheckoutSyncStatus.permissionRequired); return; }
        if (![NativeReminderAuthorization.authorized, NativeReminderAuthorization.provisional, NativeReminderAuthorization.ephemeral].contains(permission)) {
          _setStatus(NativeCheckoutSyncStatus.unavailable); return;
        }
        for (final item in plan.notifications) {
          if (!_current(generation, actor, session)) return;
          final result = await _bridge.schedule(sourceId: item.sourceId, fireAt: item.fireAt);
          if (!_current(generation, actor, session)) return;
          if (result != NativeReminderScheduleResult.scheduled) {
            await _bridge.cancelAll(preservePendingTap: true);
            if (_current(generation, actor, session)) _setStatus(result == NativeReminderScheduleResult.permissionDenied ? NativeCheckoutSyncStatus.permissionDenied : NativeCheckoutSyncStatus.unavailable);
            return;
          }
        }
        _setStatus(NativeCheckoutSyncStatus.ready);
      });
      if (_current(generation, actor, session)) {
        final pending = await _bridge.consumePendingTap();
        if (pending != null && _current(generation, actor, session)) await _handleCue(pending);
      }
    } catch (_) {
      if (_current(generation, actor, session)) _setStatus(NativeCheckoutSyncStatus.unavailable);
    }
  }

  Future<void> _handleCue(String source) async {
    final generation = _generation;
    final actor = _actor(), session = _session();
    if (actor == null || session == null || !_current(generation, actor, session)) return;
    final cueKey = '$session\n$source';
    if (!_checkingCues.add(cueKey)) return;
    try {
      final verified = await _requestGateCheck(source);
      await Future<void>.delayed(Duration.zero);
      if (source.isNotEmpty && verified && _current(generation, actor, session)) await _bridge.acknowledgePendingTap(source);
    } catch (_) {
      // Keep the OS-side pending cue for a later server retry; no local unlock.
    } finally {
      _checkingCues.remove(cueKey);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final owned = identical(_owner, this);
    if (owned) _owner = null;
    // Invoke cancellation before awaiting stream teardown. Native cancellation
    // invalidates an in-flight add and never deletes a newer attempt identifier.
    final cleanup = owned ? _bridge.cancelAll() : Future<bool>.value(true);
    await _sessionSubscription?.cancel();
    await _tapSubscription?.cancel();
    await _dueSubscription?.cancel();
    await cleanup;
    _status.value = NativeCheckoutSyncStatus.disposed;
    _status.dispose();
    _authorization.dispose();
  }
}
