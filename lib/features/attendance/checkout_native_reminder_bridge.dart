import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NativeReminderAuthorization {
  authorized,
  provisional,
  ephemeral,
  denied,
  notDetermined,
  unknown,
  unsupported,
  unavailable,
}

enum NativeReminderScheduleResult {
  scheduled,
  permissionDenied,
  cancelled,
  unavailable,
}

/// A device reminder only. A tap/due event must trigger an authorized server
/// read; neither the payload nor scheduling success is a checkout/unlock proof.
class CheckoutNativeReminderBridge {
  CheckoutNativeReminderBridge({MethodChannel? channel, bool? supported})
      : _channel = channel ?? const MethodChannel(channelName),
        _supported = supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (_supported) _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const channelName = 'com.skworks.skWorks/checkout-reminders';
  static final instance = CheckoutNativeReminderBridge();
  final MethodChannel _channel;
  final bool _supported;
  final _taps = StreamController<String>.broadcast(sync: true);
  final _due = StreamController<String>.broadcast(sync: true);
  bool _disposed = false;

  Stream<String> get taps => _taps.stream;
  Stream<String> get due => _due.stream;
  bool get isSupported => _supported && !_disposed;

  static bool validSourceId(String value) =>
      value.isNotEmpty && value.length <= 160 && RegExp(r'^[A-Za-z0-9:_-]+$').hasMatch(value);

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final source = call.arguments;
    if (_disposed || source is! String || !validSourceId(source)) return false;
    switch (call.method) {
      case 'notificationTapped':
        if (!_taps.hasListener) return false; // Native retains a cold-start tap.
        _taps.add(source);
        return false; // A fresh server check must explicitly acknowledge it.
      case 'notificationDue':
        if (!_due.hasListener) return false;
        _due.add(source);
        return true;
      default:
        return false;
    }
  }

  Future<NativeReminderAuthorization> authorizationStatus() => _authorization('status');

  /// Call only from the user's notification enable action, never on app launch.
  Future<NativeReminderAuthorization> requestPermission() => _authorization('requestPermission');

  Future<NativeReminderAuthorization> _authorization(String method) async {
    if (!isSupported) return NativeReminderAuthorization.unsupported;
    try {
      final result = await _channel.invokeMethod<Object?>(method);
      if (!isSupported) return NativeReminderAuthorization.unavailable;
      return NativeReminderAuthorization.values.firstWhere(
        (item) => item.name == result && item != NativeReminderAuthorization.unsupported &&
            item != NativeReminderAuthorization.unavailable,
        orElse: () => NativeReminderAuthorization.unknown,
      );
    } on MissingPluginException {
      return NativeReminderAuthorization.unavailable;
    } on PlatformException {
      return NativeReminderAuthorization.unavailable;
    }
  }

  Future<NativeReminderScheduleResult> schedule({required String sourceId, required DateTime fireAt}) async {
    if (!validSourceId(sourceId)) throw ArgumentError.value(sourceId, 'sourceId');
    if (!isSupported) return NativeReminderScheduleResult.unavailable;
    try {
      final result = await _channel.invokeMethod<Object?>('schedule', <String, Object>{
        'sourceId': sourceId,
        'fireAtEpochMs': fireAt.toUtc().millisecondsSinceEpoch,
        'title': 'SKO｜退勤の確認',
        'body': '退勤予定時刻です。勤務状況を確認してください。',
      });
      return isSupported && result == 'scheduled'
          ? NativeReminderScheduleResult.scheduled
          : NativeReminderScheduleResult.unavailable;
    } on PlatformException catch (error) {
      if (error.code == 'permission_denied') return NativeReminderScheduleResult.permissionDenied;
      if (error.code == 'cancelled') return NativeReminderScheduleResult.cancelled;
      return NativeReminderScheduleResult.unavailable;
    } on MissingPluginException {
      return NativeReminderScheduleResult.unavailable;
    }
  }

  Future<bool> cancel(String sourceId) async {
    if (!validSourceId(sourceId)) throw ArgumentError.value(sourceId, 'sourceId');
    return _cancel('cancel', <String, String>{'sourceId': sourceId});
  }

  /// Must be awaited at logout/account switch before scheduling the next actor.
  /// This feature's native cancellation never deletes unrelated notifications.
  Future<bool> cancelAll({bool preservePendingTap = false}) =>
      _cancel('cancelAll', preservePendingTap ? <String, Object>{'preservePendingTap': true} : null);

  Future<bool> acknowledgePendingTap(String sourceId) async {
    if (!validSourceId(sourceId)) throw ArgumentError.value(sourceId, 'sourceId');
    return _cancel('acknowledgePendingTap', <String, String>{'sourceId': sourceId});
  }

  Future<bool> _cancel(String method, Map<String, Object>? arguments) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments) == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Peek after attaching [taps]. Revalidate on the server, then call
  /// [acknowledgePendingTap]. Same-actor replanning must preserve the pending tap.
  Future<String?> consumePendingTap() async {
    if (!isSupported) return null;
    try {
      final source = await _channel.invokeMethod<Object?>('consumePendingTap');
      return isSupported && source is String && validSourceId(source) ? source : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_supported) _channel.setMethodCallHandler(null);
    await _taps.close();
    await _due.close();
  }
}
