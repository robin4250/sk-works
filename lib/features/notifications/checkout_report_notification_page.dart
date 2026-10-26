import 'dart:async';

import 'package:flutter/material.dart';

import '../../international/language_controller.dart';
import '../attendance/checkout_report_resume_action.dart';
import '../attendance/checkout_report_resume_repository.dart';
import '../daily_reports/daily_report_page.dart';
import 'checkout_report_notification_repository.dart';

String checkoutReportNotificationLabel(String state) => switch (state) {
  'report_missing' => '対象の日報を確認できません。管理者が勤務原本を確認してください。',
  'source_conflict' => '日報と退勤の対応確認が必要です。管理者に確認してください。',
  'report_input_incomplete' => '日報の必須項目が未登録です。',
  'report_choice_required' => '日報作成を始めるか選択してください。出勤表から対象勤務を選べます。',
  'checkout_deferred' => '退勤のみで記録済みです。日報を作成するときは出勤表から対象勤務を選んでください。',
  'reporter_signature_missing' => '日報の報告者サインが未登録です。',
  'reporter_saved_waiting_supervisor' => '報告者の登録は完了しています。現場責任者のサイン待ちです。',
  'signed_projection_unverified' => '日報は署名済みです。給与・勤怠への反映確認が必要です。',
  _ => '日報の状態を確認できません。',
};

class CheckoutReportNotificationPage extends StatefulWidget {
  const CheckoutReportNotificationPage({super.key, required this.reportId,
    this.source, this.resumeRepository, this.opener});
  final String reportId;
  final CheckoutReportNotificationSource? source;
  final CheckoutReportResumeRepository? resumeRepository;
  final CheckoutReportOpener? opener;
  @override State<CheckoutReportNotificationPage> createState() => _CheckoutReportNotificationPageState();
}

class _CheckoutReportNotificationPageState extends State<CheckoutReportNotificationPage> with WidgetsBindingObserver {
  CheckoutReportNotificationSource? _source;
  StreamSubscription<String?>? _events;
  String? _initialSession, _error;
  CheckoutReportNotificationSnapshot? _snapshot;
  bool _loading = true, _busy = false, _revoked = false, _foreground = true;
  int _generation = 0;
  String _t(String text) => SkoLanguageController.tr(text);
  @override void initState() {
    super.initState();
    _source = widget.source ?? CheckoutReportNotificationRepository.maybeCreate();
    _initialSession = _source?.sessionKey;
    _foreground = (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _events = _source?.sessionChanges.listen((key) {
      if (key != _initialSession || _source?.sessionKey != _initialSession) { _revoke(); }
    }, onError: (Object _) => _revoke(), onDone: _revoke);
    if (_foreground) { _load(); }
  }
  bool _active(int generation) => mounted && _foreground && !_revoked &&
    generation == _generation && _initialSession != null && _source?.sessionKey == _initialSession;
  void _revoke() {
    if (!mounted) { return; }
    setState(() { _generation++; _snapshot = null; _revoked = true; _loading = false; _busy = false;
      _error = 'ログイン状態が変わりました。通知を開き直してください。'; });
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      setState(() { _generation++; _snapshot = null; _loading = true; _busy = false; _error = null; });
    } else if (!_revoked) { _load(); }
  }
  Future<void> _load() async {
    if (_revoked || !_foreground) { return; }
    final generation = ++_generation;
    setState(() { _loading = true; _busy = false; _snapshot = null; _error = null; });
    try {
      final source = _source;
      if (source == null) { throw CheckoutReportNotificationUnavailable(); }
      final result = await source.load(widget.reportId);
      if (_active(generation)) { setState(() => _snapshot = result); }
    } catch (_) {
      if (_active(generation) || mounted && _initialSession == null) {
        setState(() => _error = '通知の日報を確認できません。対象・権限・接続を確認してください。');
      }
    } finally {
      if (mounted && generation == _generation) { setState(() => _loading = false); }
    }
  }
  bool _matchesTarget(CheckoutReportResumeTarget target, CheckoutReportNotificationItem item) {
    final index = target.sourceClockInIds.indexOf(item.sourceClockInId);
    return target.companyId == item.companyId && target.workerId == item.workerId &&
      target.reportId == widget.reportId && target.workDate == item.workDate &&
      target.siteId == item.siteId && target.routeId == item.routeId && target.needsCompletion &&
      (item.state != 'signed_projection_unverified' ||
        target.state == CheckoutReportState.partialSignature && target.reporterSignatureSaved && target.responsibleSignatureSaved) &&
      index >= 0 && index < target.clockOutIds.length && target.clockOutIds[index] == item.clockOutId;
  }

  Future<void> _resume(CheckoutReportNotificationItem selected) async {
    if (_busy || _revoked || !selected.canResume) { return; }
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final fresh = await _source!.load(widget.reportId);
      if (!mounted || !_active(generation)) { return; }
      final matches = fresh.items.where((item) => item.companyId == selected.companyId &&
        item.workerId == selected.workerId && item.sourceClockInId == selected.sourceClockInId &&
        item.clockOutId == selected.clockOutId && item.reportId == selected.reportId &&
        item.fingerprint == selected.fingerprint && item.canResume).toList();
      if (!fresh.enabled || fresh.resolved || matches.length != 1) { throw CheckoutReportNotificationUnavailable(); }
      final reader = widget.resumeRepository ?? CheckoutReportResumeRepository.maybeCreate();
      if (reader == null) { throw CheckoutReportNotificationUnavailable(); }
      final current = matches.single;
      final targets = await reader.loadDay(workerId: current.workerId, workDate: current.workDate);
      if (!mounted || !_active(generation)) { return; }
      final exact = targets.where((target) => _matchesTarget(target, current)).toList();
      if (exact.length != 1) {
        if (current.state == 'signed_projection_unverified' && targets.any((target) =>
            target.reportId == widget.reportId && const {CheckoutReportState.signedWithoutAttendance,
              CheckoutReportState.protectedPeriod}.contains(target.state))) {
          setState(() => _error = '署名済み日報の反映状態は管理者の確認が必要です。自動で再確定しません。');
          return;
        }
        throw CheckoutReportNotificationUnavailable();
      }
      await openCheckoutReportResumeTarget(context, target: exact.single, repository: reader,
        opener: (context, target) async {
          if (!_active(generation)) { throw CheckoutReportNotificationUnavailable(); }
          if (!_matchesTarget(target, current)) { throw CheckoutReportNotificationUnavailable(); }
          // A report may aggregate multiple same-day visits. Keep its validated
          // full pair set, but anchor navigation to THIS notification's pair.
          final anchored = CheckoutReportResumeTarget(companyId: target.companyId, workerId: target.workerId,
            workDate: target.workDate, sourceClockInIds: target.sourceClockInIds, clockOutIds: target.clockOutIds,
            sourceClockInId: current.sourceClockInId, clockOutId: current.clockOutId,
            state: target.state, siteId: target.siteId, routeId: target.routeId, reportId: target.reportId,
            destinationName: target.destinationName, reporterSignatureSaved: target.reporterSignatureSaved,
            responsibleSignatureSaved: target.responsibleSignatureSaved);
          if (widget.opener case final opener?) {
            await opener(context, anchored);
          } else {
            // Same normal DailyReportPage and saved anchors as stage1. This
            // callback adds the notification's sticky session check at handoff.
            await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DailyReportPage(
              initialDate: anchored.workDate, initialSiteId: anchored.siteId,
              initialRouteAssignmentId: anchored.routeId, initialReportId: anchored.reportId,
              vehicleClockInId: anchored.sourceClockInId, groupClockInAnchorId: anchored.sourceClockInId)));
          }
        });
      if (_active(generation)) { await _load(); }
    } catch (_) {
      if (_active(generation)) {
        setState(() => _error = '日報の状態が変わったか、対象を確認できません。再読み込みしてください。');
      }
    } finally {
      if (mounted && generation == _generation) { setState(() => _busy = false); }
    }
  }
  @override void dispose() {
    _generation++; _events?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  @override Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final snapshot = _snapshot;
    return Scaffold(appBar: AppBar(title: Text(_t('退勤後の日報登録')), actions: [
      IconButton(tooltip: _t('使い方'), icon: const Icon(Icons.help_outline), onPressed: () => showDialog<void>(
        context: context, builder: (dialog) => AlertDialog(title: Text(_t('退勤後の日報通知について')),
          content: Text(_t('通知を既読にしても日報の未登録は解消しません。保存済みの退勤と同じ日・勤務先の日報を再開します。もう一度出勤・退勤する必要はありません。報告者の登録、責任者のサイン待ち、署名済みの給与反映待ちは別の状態です。給与への反映済みとは、この通知だけでは判断しません。')),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(_t('閉じる')))]))),
    ]), body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_loading || _busy) const LinearProgressIndicator(),
      if (_error != null) Text(_t(_error!)),
      if (snapshot != null && !_revoked) ...[
        if (!snapshot.enabled) Text(_t('日報登録通知の提供状態を確認してください。未登録が解消したという意味ではありません。')),
        if (snapshot.enabled && snapshot.resolved) Text(_t('この日報の登録に関する未完項目はありません。給与への反映完了を示すものではありません。')),
        if (snapshot.enabled) for (final item in snapshot.items) Card(child: Padding(
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${item.workDate.year}/${item.workDate.month}/${item.workDate.day}'),
            Text(_t(checkoutReportNotificationLabel(item.state))),
            if (item.canResume) FilledButton(onPressed: _busy ? null : () => _resume(item),
              child: Text(_t(item.state == 'signed_projection_unverified' ? '日報を開く' : '対象の日報を再開'))),
          ]))),
      ],
      if (!_revoked) TextButton(onPressed: _busy ? null : _load, child: Text(_t('再読み込み'))),
    ]));
  }
}
