import 'dart:async';
import 'package:flutter/material.dart';
import 'checkout_native_reminder_bridge.dart';
import 'checkout_native_reminder_coordinator.dart';
import 'gps_auto_attendance_service.dart';
import 'gps_auto_schedule_dialog.dart';
import 'gps_work_schedule_dialog.dart';
import 'scheduled_checkout_gate.dart';
import 'scheduled_checkout_repository.dart';

/// Refreshes the existing services without treating a device notification as a
/// server completion receipt. The device coordinator owns its visible status.
class GpsWorkScheduleRuntime {
  GpsWorkScheduleRuntime._();
  static final instance = GpsWorkScheduleRuntime._();
  Future<bool> refresh() async {
    var synced = true;
    try { await GpsAutoAttendanceService.instance.refresh(); } catch (_) { synced = false; }
    await ScheduledCheckoutGateController.instance.requestCheck();
    unawaited(CheckoutNativeReminderCoordinator.refreshCurrent());
    return synced;
  }
}

/// Keeps the saved configuration revision while a user edits the two-time
/// dialog. Another device's changes cause a server CAS failure, not overwrite.
class GpsWorkScheduleSelection {
  GpsWorkScheduleSelection._(this._repository, this._actorIdentity, this.draft, this.expectedRevision);
  final ScheduledCheckoutRepository _repository;
  final String _actorIdentity;
  final GpsWorkScheduleDraft draft;
  final int expectedRevision;
  static Future<GpsWorkScheduleSelection> load({ScheduledCheckoutRepository? repository,
    String? siteId, String? routeId, List<int> fallbackWeekdays = const [1,2,3,4,5],
    TimeOfDay fallbackClockIn = const TimeOfDay(hour:8,minute:0)}) async {
    final repo = repository ?? ScheduledCheckoutRepository.maybeCreate();
    if (repo == null) { throw StateError('出退勤時刻の設定を利用できません。'); }
    final identity = repo.currentSessionIdentity;
    final plan = await repo.loadNotificationPlan();
    if (identity == null || repo.currentSessionIdentity != identity || plan.actorId != repo.actorId) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    }
    final exact = plan.configurations.where((c) =>
        (siteId != null && c.siteId == siteId) || (routeId != null && c.routeId == routeId)).toList();
    if (exact.length > 1 || (exact.isEmpty && plan.configurations.length > 1)) {
      throw StateError('出退勤時刻を設定する会社・社員を確認してください。');
    }
    final configuration = exact.isNotEmpty ? exact.single : plan.configurations.isEmpty ? null : plan.configurations.single;
    final draft = GpsWorkScheduleDraft(weekdays: configuration?.weekdays ?? fallbackWeekdays,
      clockIn: configuration == null ? fallbackClockIn : gpsTimeFromDatabase(configuration.clockInTime),
      checkoutReminder: configuration == null ? const TimeOfDay(hour:17,minute:0) : gpsTimeFromDatabase(configuration.checkoutTime));
    return GpsWorkScheduleSelection._(repo,identity,draft,configuration?.revision ?? 0);
  }
  Future<GpsWorkScheduleSelection?> choose(BuildContext context) async {
    final edited = await showGpsWorkScheduleDialog(context,initialWeekdays:draft.weekdays,
      initialClockIn:draft.clockIn,initialCheckoutReminder:draft.checkoutReminder);
    if (edited == null || !context.mounted) { return null; }
    if (_repository.currentSessionIdentity != _actorIdentity) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    }
    return GpsWorkScheduleSelection._(_repository,_actorIdentity,edited,expectedRevision);
  }
  Future<bool> save(BuildContext context, {String? siteId,String? routeId}) async {
    if ((siteId == null) == (routeId == null)) {
      throw StateError('GPS自動出勤は固定現場またはルートを選択してください。');
    }
    if (_repository.currentSessionIdentity != _actorIdentity) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    }
    final allowed = await ensureGpsAutoLocationPermission(context);
    if (!allowed || !context.mounted) { return false; }
    // This method runs only from the user's Save action. Denial does not claim
    // OS delivery: persisted foreground confirmation remains independently valid.
    final permission = await CheckoutNativeReminderBridge.instance.requestPermission();
    if (!context.mounted) { return false; }
    if (_repository.currentSessionIdentity != _actorIdentity) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    }
    await _repository.save(siteId:siteId,routeId:routeId,weekdays:draft.weekdays,
      clockInTime:draft.clockInDatabase,checkoutTime:draft.checkoutDatabase,expectedRevision:expectedRevision);
    final synced = await GpsWorkScheduleRuntime.instance.refresh();
    final permitted = const {NativeReminderAuthorization.authorized,NativeReminderAuthorization.provisional,
      NativeReminderAuthorization.ephemeral}.contains(permission);
    if (context.mounted && (!synced || !permitted)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text(
        '出退勤設定を保存しました。通知が使えない場合は、アプリを開いた時に退勤を確認してください。')));
    }
    return true;
  }
}
