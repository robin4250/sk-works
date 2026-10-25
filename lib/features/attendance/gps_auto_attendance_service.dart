import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'attendance_verification_repository.dart';
import 'scheduled_checkout_gate.dart';
import 'checkout_native_reminder_coordinator.dart';

class GpsAutoAttendanceService {
  GpsAutoAttendanceService._();

  static final GpsAutoAttendanceService instance =
      GpsAutoAttendanceService._();

  StreamSubscription<Position>? _subscription;
  DateTime? _lastAttemptAt;
  bool _starting = false;

  Future<void> startIfConfigured() async {
    if (_starting) return;
    _starting = true;
    try {
      final repository = AttendanceVerificationRepository.maybeCreate();
      if (repository == null) {
        await stop();
        return;
      }

      final workspace = await repository.loadAttendanceSelectionWorkspace();
      final schedule = workspace['gps_schedule'] is Map
          ? Map<String, dynamic>.from(workspace['gps_schedule'] as Map)
          : const <String, dynamic>{};

      if (schedule['enabled'] != true) {
        await stop();
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        await stop();
        return;
      }

      if (_subscription != null) return;

      final settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );

      _subscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        _onPosition,
        onError: (_) {},
      );
    } finally {
      _starting = false;
    }
  }

  Future<void> refresh() async {
    await stop();
    await startIfConfigured();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastAttemptAt = null;
  }

  Future<void> _onPosition(Position position) async {
    final now = DateTime.now();
    final last = _lastAttemptAt;
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _lastAttemptAt = now;

    final repository = AttendanceVerificationRepository.maybeCreate();
    if (repository == null) return;

    try {
      final result = await repository.attemptGpsAutoAttendance(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
      );
      if (result['status'] == 'clocked_in') {
        await ScheduledCheckoutGateController.instance.requestCheck();
        unawaited(CheckoutNativeReminderCoordinator.refreshCurrent());
      }
    } catch (_) {
      // The next Core Location update retries. Server-side checks remain
      // idempotent for the scheduled day.
    }
  }
}
