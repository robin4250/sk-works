// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../shared/pdf_bytes_cache.dart';
import 'daily_report_pdf_evidence.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import '../notifications/saved_group_report_publication.dart';
import '../notifications/saved_report_notification_retry_store.dart';
import '../../international/language_controller.dart';
import '../operations/odometer_text_recognition_engine.dart';
import 'daily_report_pdf_service.dart';
import '../operations/vehicle_driver_meter_page.dart';
import 'daily_report_pending_notice.dart';
import 'daily_report_repository.dart';
import 'signature_capture_page.dart';

class DailyReportPage extends StatefulWidget {
  const DailyReportPage({
    super.key,
    this.initialDate,
    this.initialSiteId,
    this.initialRouteAssignmentId,
    this.vehicleClockInId,
    this.groupClockInAnchorId,
  });

  final DateTime? initialDate;
  final String? initialSiteId;
  final String? initialRouteAssignmentId;
  final String? vehicleClockInId;
  final String? groupClockInAnchorId;

  @override
  State<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends State<DailyReportPage> {
  final _repository = DailyReportRepository.maybeCreate();
  String? _evidenceAttachmentFingerprint;
  final _workDescription = TextEditingController();
  final _picker = ImagePicker();
  final _odometerRecognition = const OdometerTextRecognitionEngine();

  late DateTime _date;
  List<DailyReportSiteGroup> _groups = const [];
  String? _siteId;
  String? _routeAssignmentId;
  String? _siteName;
  List<DailyReportWorkerDraft> _workers = [];
  DailyReportRecord? _report;
  List<DailyReportEvidenceRecord> _evidence = const [];
  bool _loading = true;
  bool _saving = false;
  String? _notificationRetryReportId;
  final _notificationRetries = SavedReportNotificationRetryStore();
  SavedReportNotificationRetry? _notificationRetry;
  int _loadGeneration = 0;
  String? _savedDraftFingerprint;
  String? _error;

  final Map<String, TextEditingController> _overtime = {};
  final Map<String, TextEditingController> _early = {};
  final Map<String, TextEditingController> _night = {};
  final Map<String, TextEditingController> _allowanceLabel = {};
  final Map<String, TextEditingController> _odometer = {};

  bool get _signed => _report?.signed == true;

  String? get _currentGroupAnchor {
    final date = widget.initialDate;
    if (date == null || _siteId != widget.initialSiteId || _routeAssignmentId != null ||
        _date.year != date.year || _date.month != date.month || _date.day != date.day) {
      return null;
    }
    return widget.groupClockInAnchorId;
  }

  String? get _currentVehicleAnchor {
    final date = widget.initialDate;
    if (date == null || _siteId != widget.initialSiteId || _routeAssignmentId != widget.initialRouteAssignmentId ||
        _date.year != date.year || _date.month != date.month || _date.day != date.day) {
      return null;
    }
    return widget.vehicleClockInId;
  }

  bool get _editable => !_signed && !_saving;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
    _siteId = widget.initialSiteId;
    _routeAssignmentId = widget.initialRouteAssignmentId;
    _loadDay();
    _restoreNotificationRetry();
  }

  @override
  void dispose() {
    _workDescription.dispose();
    _disposeWorkerControllers();
    super.dispose();
  }

  void _disposeWorkerControllers() {
    for (final controller in [
      ..._overtime.values,
      ..._early.values,
      ..._night.values,
      ..._allowanceLabel.values,
      ..._odometer.values,
    ]) {
      controller.dispose();
    }
    _overtime.clear();
    _early.clear();
    _night.clear();
    _allowanceLabel.clear();
    _odometer.clear();
  }

  Future<void> _loadDay() async {
    final generation = ++_loadGeneration;
    final date = _date;
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = SkoLanguageController.tr('日報機能を利用できません。');
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await repository.loadClockedInGroups(date);
      if (!mounted || generation != _loadGeneration) return;

      DailyReportSiteGroup? selected;
      if (_siteId != null) {
        selected = groups
            .where((g) => g.siteId == _siteId)
            .firstOrNull;
      } else if (_routeAssignmentId != null) {
        selected = groups
            .where((g) => g.routeAssignmentId == _routeAssignmentId)
            .firstOrNull;
      }
      selected ??= groups.firstOrNull;

      setState(() {
        _groups = groups;
        _siteId = selected?.siteId;
        _routeAssignmentId = selected?.routeAssignmentId;
        _siteName = selected?.siteName;
      });

      await _loadSelectedSite();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadSelectedSite() async {
    final generation = ++_loadGeneration;
    final date = _date;
    final repository = _repository;
    final siteId = _siteId;
    final routeAssignmentId = _routeAssignmentId;
    if (repository == null ||
        (siteId == null && routeAssignmentId == null)) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _report = null;
        _workers = [];
        _evidence = const [];
        _loading = false;
      });
      _resetWorkerControllers();
      _savedDraftFingerprint = _draftFingerprint();
      return;
    }

    try {
      final existing = await repository.loadReport(
        date: date,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
        vehicleClockInAnchorId: _currentVehicleAnchor,
      );
      final evidence = await repository.loadAttendanceEvidence(
        reportId: existing?.id,
        date: date,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
      );
      if (!mounted || generation != _loadGeneration) return;

      final group = _groups
          .where(
            (g) =>
                g.siteId == siteId &&
                g.routeAssignmentId == routeAssignmentId,
          )
          .firstOrNull;
      var workers = existing?.workers.isNotEmpty == true
          ? existing!.workers
          : List<DailyReportWorkerDraft>.from(group?.workers ?? const []);
      final anchor = _currentGroupAnchor;
      if (anchor != null) {
        workers = await repository.loadAnchoredWorkers(anchorId: anchor, workDate: date,
          existing: workers, fallback: List<DailyReportWorkerDraft>.from(group?.workers ?? const []),
          allowNewMembers: existing?.signed != true);
        if (!mounted || generation != _loadGeneration) return;
      }


      final meterEnabled = await repository.vehicleMeterEnabledForAnchor(_currentVehicleAnchor);
      if (meterEnabled) {
        for (final worker in workers.where((worker) => worker.vehicleId != null)) {
          worker.meterManaged = true;
        }
      }
      if (!mounted || generation != _loadGeneration) return;

      setState(() {
        _error = null;
        _report = existing;
        _siteName = existing?.siteName ?? group?.siteName ?? '';
        _workers = workers;
        _evidence = evidence;
        _workDescription.text = existing?.workDescription ?? '';
        _loading = false;
      });
      _resetWorkerControllers();
      _savedDraftFingerprint = _draftFingerprint();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _resetWorkerControllers() {
    _disposeWorkerControllers();
    for (final worker in _workers) {
      _overtime[worker.workerId] =
          TextEditingController(text: _number(worker.overtimeHours));
      _early[worker.workerId] =
          TextEditingController(text: _number(worker.earlyHours));
      _night[worker.workerId] =
          TextEditingController(text: _number(worker.nightHours));
      _allowanceLabel[worker.workerId] =
          TextEditingController(text: worker.allowanceLabel);
      _odometer[worker.workerId] = TextEditingController(
        text: worker.odometerKm == null ? '' : _number(worker.odometerKm!),
      );
    }
  }

  Future<void> _pickDate() async {
    if (_saving) return;
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected == null || !mounted || _saving) return;
    setState(() {
      _date = selected;
      _siteId = null;
      _routeAssignmentId = null;
    });
    await _loadDay();
  }

  Future<void> _selectSite(String? destinationKey) async {
    if (destinationKey == null || _saving || !mounted) return;
    final group = _groups
        .where((item) => item.destinationKey == destinationKey)
        .firstOrNull;
    if (group == null) return;
    if (group.siteId == _siteId &&
        group.routeAssignmentId == _routeAssignmentId) {
      return;
    }
    setState(() {
      _siteId = group.siteId;
      _routeAssignmentId = group.routeAssignmentId;
      _siteName = group.siteName;
      _loading = true;
    });
    await _loadSelectedSite();
  }

  void _applyControllers() {
    for (final worker in _workers) {
      worker.overtimeHours =
          double.tryParse(_overtime[worker.workerId]?.text ?? '') ?? 0;
      worker.earlyHours =
          double.tryParse(_early[worker.workerId]?.text ?? '') ?? 0;
      worker.nightHours =
          double.tryParse(_night[worker.workerId]?.text ?? '') ?? 0;
      // Preserve the saved monetary value; employee reports do not edit money.
      worker.allowanceLabel =
          _allowanceLabel[worker.workerId]?.text.trim() ?? '';
      if (worker.vehicleId != null && !worker.meterManaged) {
        worker.odometerKm = double.tryParse(
          _odometer[worker.workerId]?.text.trim() ?? '',
        );
      }
    }
  }

  String _draftFingerprint() {
    _applyControllers();
    return jsonEncode({
      'description': _workDescription.text.trim(),
      'workers': _workers.map((worker) => {
        ...worker.toRpcJson(),
        'vehicle_id': worker.vehicleId,
        'route_id': worker.routeId,
        'odometer_km': worker.odometerKm,
        'source_clock_in_id': worker.sourceClockInId,
        'source_clock_out_at': worker.sourceClockOutAt?.toIso8601String(),
        'vehicle_meter_event_id': worker.meterEventId,
        'vehicle_meter_source_clock_in_id': worker.meterSourceClockInId,
        'previous_odometer_km': worker.previousOdometerKm,
        'trip_distance_km': worker.tripDistanceKm,
      }).toList(),
    });
  }

  Future<String?> _saveBeforeSignature() async {
    if (_signed) return _report?.id;
    if (_workers.any((worker) => worker.meterManaged && worker.meterEventId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください'))));
      return null;
    }
    if (_workers.any((worker) => worker.sourceClockInId != null && worker.sourceClockOutAt == null)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('未退勤のメンバーがいます。下書き保存後、退勤を確認して日報を再読み込みしてください'))));
      return null;
    }
    if (((_currentGroupAnchor != null && _workers.any((worker) => worker.sourceClockInId != null)) ||
         (_currentVehicleAnchor != null && _workers.any((worker) => worker.meterManaged))) &&
        _evidenceAttachmentFingerprint != _draftFingerprint()) {
      final id = await _saveDraft(ownsBusyState: false);
      if (_workers.any((worker) => worker.meterManaged && worker.meterEventId == null)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください'))));
        }
        return null;
      }
      return id;
    }
    if (_report != null && _savedDraftFingerprint == _draftFingerprint()) {
      return _report!.id;
    }
    final id = await _saveDraft(ownsBusyState: false);
    if (_workers.any((worker) => worker.meterManaged && worker.meterEventId == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('運転手のメーター登録が未完了です。下書き保存後、登録を確認して日報を再読み込みしてください'))));
      }
      return null;
    }
    return id;
  }

  Future<void> _captureOdometer(
    DailyReportWorkerDraft worker,
  ) async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (photo == null) return;

    OdometerRecognitionResult result;
    try {
      result = await _odometerRecognition.recognizeImagePath(photo.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.trParams('メーターを読み取れませんでした: {error}', {'error': error}))),
      );
      return;
    }

    if (!mounted) return;
    final controller = TextEditingController(
      text: result.bestCandidate == null
          ? ''
          : _number(result.bestCandidate!),
    );

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.tr('メーター読取結果')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              SkoLanguageController.tr('数値が合っていれば登録してください。違う場合は手入力で修正するか、再撮影できます。'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: SkoLanguageController.tr('走行距離'),
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: Text(SkoLanguageController.tr('再撮影')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'use'),
            child: Text(SkoLanguageController.tr('この数値を登録')),
          ),
        ],
      ),
    );

    if (action == 'retry') {
      controller.dispose();
      await _captureOdometer(worker);
      return;
    }

    if (action == 'use') {
      final value = double.tryParse(controller.text.trim());
      if (value == null || value < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(SkoLanguageController.tr('走行距離を数字で入力してください'))),
          );
        }
      } else {
        _odometer[worker.workerId]?.text = _number(value);
        worker.odometerKm = value;
        if (mounted) setState(() {});
      }
    }
    controller.dispose();
  }

  // Only the explicit registration action publishes. Internal draft saves for
  // signatures, previews and reloads never publish notifications.
  Future<void> _register() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final completeGroup = groupReportPublicationEligible(
        anchorSourceId: _currentGroupAnchor, siteId: _siteId,
        routeAssignmentId: _routeAssignmentId,
        roster: _workers.map((worker) => (
          sourceId: worker.sourceClockInId, clockOutAt: worker.sourceClockOutAt)),
      );
      await registerSavedGroupReport(
        notificationEligible: completeGroup,
        save: () => _saveDraft(ownsBusyState: false),
        publish: (id) async {
          final retry = _report?.notificationRetryScope;
          if (retry == null || retry.reportId != id) {
            throw StateError('登録済み日報を確認できません');
          }
          await _publishSavedReport(retry);
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreNotificationRetry() async {
    final userId = _repository?.notificationRetryUserId;
    if (userId == null) return;
    try {
      final pending = await _notificationRetries.load(userId);
      if (!mounted || _repository?.notificationRetryUserId != userId) return;
      setState(() {
        _notificationRetry = pending.firstOrNull;
        _notificationRetryReportId = _notificationRetry?.reportId;
      });
    } catch (_) {
      // Corrupt or unreadable storage is retained, never reset to an empty list.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('保存済み通知の再確認情報を読み込めません。保存内容は保持しています'),
        )));
      }
    }
  }

  Future<void> _publishSavedReport(SavedReportNotificationRetry retry) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      final sent = await retryPersistedSavedReportNotification(retry,
        remember: _notificationRetries.remember,
        verifySaved: repository.verifySavedNotificationScope,
        publish: (id) {
          if (repository.notificationRetryUserId != retry.userId) {
            throw StateError('日報通知の利用者が変更されています');
          }
          return repository.publishSavedGroupReportNotifications(id);
        },
        confirmed: _notificationRetries.confirmed,
      );
      await _restoreNotificationRetry();
      if (!sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('日報は登録済みです。通知結果は未確認です。同じ日報の通知のみ再確認できます'),
        )));
      }
    } catch (_) {
      await _restoreNotificationRetry();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        SkoLanguageController.tr('日報は登録済みです。メンバー通知の結果は未確認です。通知のみ再確認できます'),
      )));
    }
  }

  Future<void> _retrySavedReportNotification() async {
    final repository = _repository;
    final userId = repository?.notificationRetryUserId;
    if (_saving || _notificationRetry == null || repository == null || userId == null) return;
    setState(() => _saving = true);
    try {
      // Every stored identity is checked independently. OFF/zero for the oldest
      // report cannot block later pending reports; no new report is saved.
      final pending = await _notificationRetries.load(userId);
      for (final retry in pending) {
        if (!mounted || repository.notificationRetryUserId != userId) break;
        await _publishSavedReport(retry);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          SkoLanguageController.tr('保存済み通知の再確認情報を読み込めません。保存内容は保持しています'),
        )));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _saveDraft({bool ownsBusyState = true}) async {
    if (ownsBusyState && _saving) return null;
    final repository = _repository;
    final siteId = _siteId;
    final routeAssignmentId = _routeAssignmentId;
    if (repository == null ||
        (siteId == null && routeAssignmentId == null)) {
      return null;
    }

    _applyControllers();

    final missingOdometer = _workers.where(
      (worker) => worker.vehicleId != null && !worker.meterManaged && worker.odometerKm == null,
    );
    if (missingOdometer.isNotEmpty) {
      final names = missingOdometer.map((worker) => worker.workerName).join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.trParams('{names} の退勤時走行距離を入力してください', {'names': names}),
          ),
        ),
      );
      return null;
    }

    if (ownsBusyState) setState(() => _saving = true);
    try {
      final id = await repository.saveDraft(
        reportId: _report?.id,
        siteId: siteId,
        routeAssignmentId: routeAssignmentId,
        date: _date,
        workDescription: _workDescription.text,
        workers: _workers,
        groupClockInAnchorId: _currentGroupAnchor,
        vehicleClockInAnchorId: _currentVehicleAnchor,
      );
      if (!mounted) return id;
      _evidenceAttachmentFingerprint = _draftFingerprint();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('日報を登録しました'))),
      );
      await _loadSelectedSite();
      if (!mounted || _error != null || _report?.id != id) return null;
      return id;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${SkoLanguageController.tr('登録できませんでした')}: $error')),
      );
      return null;
    } finally {
      if (mounted && ownsBusyState) setState(() => _saving = false);
    }
  }

  Future<void> _signReporter() async {
    if (_saving || _signed) return;
    setState(() => _saving = true);
    try {
      final reportId = await _saveBeforeSignature();
      if (reportId == null || !mounted) return;
      final result = await Navigator.of(context).push<SignatureResult>(
        MaterialPageRoute(builder: (_) => SignatureCapturePage(
          title: SkoLanguageController.tr('報告者サイン'),
          signerLabel: SkoLanguageController.tr('報告者名'),
          submitLabel: SkoLanguageController.tr('報告者サインを保存'),
        )),
      );
      if (result == null || !mounted) return;
      final repository = _repository;
      if (repository == null) return;
      await repository.saveReporterSignature(
        reportId: reportId, signerName: result.signerName,
        signatureJson: result.toJson(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('報告者サインを保存しました')),
      ));
      await _loadSelectedSite();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.trParams('報告者サインを保存できませんでした: {error}', {'error': error})),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sign() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final reportId = await _saveBeforeSignature();
      if (reportId == null || !mounted) return;
      // Saving changes invalidates the earlier reporter signature server-side.
      if (_report?.reporterSignatureJson == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.tr('編集内容を保存した場合は、報告者サインを再登録してから確定してください')),
        ));
        return;
      }
      final result = await Navigator.of(context).push<SignatureResult>(
        MaterialPageRoute(builder: (_) => SignatureCapturePage(
          title: SkoLanguageController.tr('責任者サイン'),
          signerLabel: SkoLanguageController.tr('現場責任者名'),
          submitLabel: SkoLanguageController.tr('責任者サインで確定'),
        )),
      );
      if (result == null || !mounted) return;
      final repository = _repository;
      if (repository == null) return;
      await repository.sign(reportId: reportId,
        signerName: result.signerName, signatureJson: result.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SkoLanguageController.tr('責任者サインで日報を確定しました')),
      ));
      await _loadSelectedSite();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(SkoLanguageController.trParams('確定できませんでした: {error}', {'error': error})),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestEdit() async {
    if (_saving) return;
    final report = _report;
    final repository = _repository;
    if (report == null || repository == null) return;

    final reason = TextEditingController();
    setState(() => _saving = true);
    try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(SkoLanguageController.tr('確定済み日報を修正')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              SkoLanguageController.tr('確定済みの日報は直接変更できません。会社で設定した承認担当者（1〜3名）へ承認依頼を送ります。'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: InputDecoration(labelText: SkoLanguageController.tr('修正理由（任意）')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(SkoLanguageController.tr('キャンセル')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(SkoLanguageController.tr('承認依頼を送る')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
      await repository.requestEdit(
        reportId: report.id,
        reason: reason.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.tr('承認依頼を送りました。設定された承認担当者の承認後、日報を開いて編集できます。'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.trParams('承認依頼を送れませんでした: {error}', {'error': error}))),
      );
    } finally {
      reason.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSignature() async {
    final report = _report;
    if (report == null) return;
    final signature =
        report.responsibleSignatureJson ?? report.signatureJson;
    if (signature == null) return;
    final strokes = SignatureResult.fromJson(signature);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          SkoLanguageController.trParams('責任者サイン：{name}', {'name': report.responsibleSignerName ?? report.signerName ?? ''}),
        ),
        content: SizedBox(
          width: 460,
          child: SignaturePreview(strokes: strokes, height: 220),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(SkoLanguageController.tr('閉じる')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          SkoLanguageController.tr('日報'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      bottomNavigationBar: _notificationRetryReportId == null ? null : SafeArea(
        child: Padding(padding: const EdgeInsets.all(12), child: OutlinedButton.icon(
          onPressed: _saving ? null : _retrySavedReportNotification,
          icon: const Icon(Icons.notifications_outlined),
          label: Text(SkoLanguageController.tr('登録済み日報の通知のみ再確認')),
        )),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadDay)
                : _groups.isEmpty
                    ? _EmptyDay(date: _date, onPickDate: _pickDate)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        children: [
                          _HeaderField(
                            icon: Icons.calendar_today_outlined,
                            label: SkoLanguageController.tr('日付'),
                            value:
                                '${_date.year}/${_two(_date.month)}/${_two(_date.day)}',
                            onTap: _saving ? null : _pickDate,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _groups
                                .where(
                                  (g) =>
                                      g.siteId == _siteId &&
                                      g.routeAssignmentId ==
                                          _routeAssignmentId,
                                )
                                .map((g) => g.destinationKey)
                                .firstOrNull,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.tr('現場／ルート'),
                              prefixIcon: Icon(Icons.route_outlined),
                            ),
                            items: [
                              for (final group in _groups)
                                DropdownMenuItem(
                                  value: group.destinationKey,
                                  child: Text(
                                    group.routeAssignmentId == null
                                        ? group.siteName
                                        : SkoLanguageController.trParams('ルート：{name}', {'name': group.siteName}),
                                  ),
                                ),
                            ],
                            onChanged: _saving ? null : _selectSite,
                          ),
                          const SizedBox(height: 16),
                          _MemberSummary(workers: _workers),
                          DailyReportPendingNotice(
                            hasClockedInWorkers: _groups.any((group) =>
                              group.siteId == _siteId &&
                              group.routeAssignmentId == _routeAssignmentId &&
                              group.workers.isNotEmpty),
                            isSigned: _signed,
                          ),
                          if (_evidence.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.photo_camera_outlined),
                                ),
                                title: Text(
                                  SkoLanguageController.tr('出勤確認写真'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  SkoLanguageController.trParams('{count}枚 / この日報に紐付いています', {'count': _evidence.length}),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DailyReportEvidencePage(
                                      date: _date,
                                      siteName: _siteName ?? '',
                                      items: _evidence,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (widget.vehicleClockInId != null)
                            VehicleDriverMeterEntry(
                              sourceClockInId: widget.vehicleClockInId!,
                              expectedSiteId: _siteId,
                              expectedRouteId: _routeAssignmentId,
                              requireDestinationMatch: true,
                              expectedWorkDate: '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                            ),
                          TextField(
                            controller: _workDescription,
                            enabled: _editable,
                            minLines: 6,
                            maxLines: 12,
                            decoration: InputDecoration(
                              labelText: SkoLanguageController.tr('作業内容'),
                              alignLabelWithHint: true,
                              hintText: SkoLanguageController.tr('本日の作業内容を入力'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            SkoLanguageController.tr('メンバー別 残業・早出・手当'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          for (final worker in _workers) ...[
                            _WorkerDetailCard(
                              worker: worker,
                              editable: _editable,
                              overtime: _overtime[worker.workerId]!,
                              early: _early[worker.workerId]!,
                              night: _night[worker.workerId]!,
                              allowanceLabel:
                                  _allowanceLabel[worker.workerId]!,
                              odometer: _odometer[worker.workerId]!,
                              onCaptureOdometer: () =>
                                  _captureOdometer(worker),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  _report?.reporterSignatureJson == null
                                      ? Icons.draw_outlined
                                      : Icons.check,
                                ),
                              ),
                              title: Text(
                                SkoLanguageController.tr('報告者サイン'),
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              subtitle: Text(
                                _report?.reporterSignatureJson == null
                                    ? SkoLanguageController.tr('日報を作成した報告者がサインします')
                                    : _report?.reporterSignerName ?? SkoLanguageController.tr('報告者サイン済み'),
                              ),
                              trailing: _signed
                                  ? null
                                  : const Icon(Icons.chevron_right),
                              onTap: _saving || _signed ? null : _signReporter,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_signed)
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.check),
                                ),
                                title: Text(
                                  SkoLanguageController.tr('責任者サイン済み・確定'),
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  _report?.responsibleSignerName ?? _report?.signerName ?? SkoLanguageController.tr('責任者サイン済み'),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _showSignature,
                              ),
                            )
                          else
                            Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.draw_outlined),
                                ),
                                title: Text(
                                  SkoLanguageController.tr('責任者サイン'),
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                subtitle: Text(
                                  SkoLanguageController.tr('報告者サインの後、責任者サインで日報と出勤データを確定します'),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: _saving ? null : _sign,
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (!_signed)
                            FilledButton.icon(
                              onPressed: _saving ? null : _register,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(SkoLanguageController.tr('登録')),
                            ),
                          if (_signed)
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _requestEdit,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(SkoLanguageController.tr('編集・修正を申請')),
                            ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DailyReportPrintPreviewPage(
                                  date: _date,
                                  siteName: _siteName ?? '',
                                  workers: _workers,
                                  workDescription: _workDescription.text,
                                  report: _report,
                                  evidence: _evidence,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.print_outlined),
                            label: Text(SkoLanguageController.tr('A4印刷プレビュー')),
                          ),
                        ],
                      ),
      ),
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _WorkerDetailCard extends StatelessWidget {
  const _WorkerDetailCard({
    required this.worker,
    required this.editable,
    required this.overtime,
    required this.early,
    required this.night,
    required this.allowanceLabel,
    required this.odometer,
    required this.onCaptureOdometer,
  });

  final DailyReportWorkerDraft worker;
  final bool editable;
  final TextEditingController overtime;
  final TextEditingController early;
  final TextEditingController night;
  final TextEditingController allowanceLabel;
  final TextEditingController odometer;
  final VoidCallback onCaptureOdometer;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          worker.workerName,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            SkoLanguageController.tr('個別の残業・早出・手当を設定'),
            if (worker.sourceClockInId != null)
              SkoLanguageController.tr(worker.sourceClockOutAt == null
                ? '退勤未登録・確定前に確認' : '退勤済み・元勤務と連携'),
            if (worker.vehicleName?.trim().isNotEmpty == true)
              SkoLanguageController.trParams('車両：{name}', {'name': worker.vehicleName!}),
            if (worker.routeName?.trim().isNotEmpty == true)
              SkoLanguageController.trParams('ルート：{name}', {'name': worker.routeName!}),
          ].join(' / '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (worker.vehicleName?.trim().isNotEmpty == true ||
              worker.routeName?.trim().isNotEmpty == true) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                [
                  if (worker.vehicleName?.trim().isNotEmpty == true)
                    SkoLanguageController.trParams('車両：{name}', {'name': worker.vehicleName!}),
                  if (worker.routeName?.trim().isNotEmpty == true)
                    SkoLanguageController.trParams('ルート：{name}', {'name': worker.routeName!}),
                ].join('　'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (worker.meterManaged) ...[
            Text(SkoLanguageController.tr(worker.meterEventId == null
              ? '運転手のメーター登録待ち' : '車両距離は運転手の登録記録から表示します')),
            if (worker.previousOdometerKm != null)
              Text('${SkoLanguageController.tr('前回距離')}: ${worker.previousOdometerKm} km'),
            if (worker.meterEventId != null && worker.odometerKm != null)
              Text('${SkoLanguageController.tr('今回距離')}: ${worker.odometerKm} km'),
            if (worker.tripDistanceKm != null)
              Text('${SkoLanguageController.tr('当日の走行距離')}: ${worker.tripDistanceKm} km'),
            const SizedBox(height: 10),
          ],
          if (worker.vehicleId != null && !worker.meterManaged) ...[
            TextField(
              controller: odometer,
              enabled: editable,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: SkoLanguageController.tr('退勤時の走行距離'),
                suffixText: 'km',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: editable ? onCaptureOdometer : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(SkoLanguageController.tr('メーターを撮影して読取')),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: overtime,
                  label: SkoLanguageController.tr('残業(h)'),
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: early,
                  label: SkoLanguageController.tr('早出(h)'),
                  enabled: editable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  controller: night,
                  label: SkoLanguageController.tr('夜間(h)'),
                  enabled: editable,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: allowanceLabel,
            enabled: editable,
            decoration: InputDecoration(
              labelText: SkoLanguageController.tr('手当名'),
              hintText: SkoLanguageController.isEnglish
                  ? 'e.g. Steel, PC'
                  : SkoLanguageController.tr('例：鉄骨、PC'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _MemberSummary extends StatelessWidget {
  const _MemberSummary({required this.workers});

  final List<DailyReportWorkerDraft> workers;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              SkoLanguageController.trParams('朝の出勤メンバー  {count}名', {'count': workers.length}),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final worker in workers)
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(worker.workerName),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderField extends StatelessWidget {
  const _HeaderField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({
    required this.date,
    required this.onPickDate,
  });

  final DateTime date;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 54),
            const SizedBox(height: 12),
            Text(
              SkoLanguageController.tr('この日の出勤メンバーがまだありません'),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              SkoLanguageController.tr('朝の出勤登録が行われると、現場とメンバーが日報へ自動表示されます。'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(SkoLanguageController.tr('日付を変更')),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyReportEvidencePage extends StatelessWidget {
  const DailyReportEvidencePage({
    super.key,
    required this.date,
    required this.siteName,
    required this.items,
  });

  final DateTime date;
  final String siteName;
  final List<DailyReportEvidenceRecord> items;

  Future<void> _openEvidenceLocation(
    BuildContext context,
    DailyReportEvidenceRecord item,
  ) async {
    if (!item.hasLocation) return;
    final query = '${item.latitude},${item.longitude}';
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('位置情報を地図で開けませんでした'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final repository = DailyReportRepository.maybeCreate();
    return Scaffold(
      appBar: AppBar(
        title: Text(SkoLanguageController.tr('出勤確認写真一覧')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                date.year.toString() +
                    '/' +
                    date.month.toString().padLeft(2, '0') +
                    '/' +
                    date.day.toString().padLeft(2, '0'),
              ),
              subtitle: Text(siteName),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.workerName +
                          ' / ' +
                          (item.eventType == 'route_stop' ? SkoLanguageController.tr('途中現場') : item.eventType == 'clock_out' ? SkoLanguageController.tr('退勤') : SkoLanguageController.tr('出勤')),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.confirmedAt.hour.toString().padLeft(2, '0') +
                          ':' +
                          item.confirmedAt.minute.toString().padLeft(2, '0'),
                    ),
                    if (item.hasLocation) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () => _openEvidenceLocation(context, item),
                        icon: const Icon(Icons.location_on_outlined),
                        label: Text(
                          item.accuracyM == null
                              ? SkoLanguageController.tr('位置を地図で確認')
                              : SkoLanguageController.trParams('位置を地図で確認（精度 約{accuracy}m）', {'accuracy': item.accuracyM!.round()}),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (item.stopLabel != null) Text('${SkoLanguageController.tr('対象現場')}: ${item.stopLabel}'),
                    if (item.originKind != null) Text(SkoLanguageController.tr(item.originKind == 'company' ? '会社出勤後に現場へ' : '直行直帰')),
                    if (item.photoObservedAt != null) Text('${SkoLanguageController.tr('写真観測時刻')}: ${item.photoObservedAt!.toIso8601String()}'),
                    if (item.photoStatus != null)
                      Text(item.photoCapturedAt == null
                        ? SkoLanguageController.tr(item.eventType == 'route_stop' ? '撮影日時未取得（表示時刻は途中現場の記録時刻）' : '撮影日時未取得（表示時刻は勤怠登録時刻）')
                        : '${SkoLanguageController.tr('撮影日時')}: ${item.photoCapturedAt!.toIso8601String()}'),
                    if (item.gpsStatus != null && item.capturedAddress?.trim().isNotEmpty != true)
                      Text(SkoLanguageController.tr('撮影住所未取得')),
                    if (item.capturedAddress?.trim().isNotEmpty == true)
                      Text(item.capturedAddress!),
                    if (item.photoStatus != null)
                      Text(SkoLanguageController.trParams('写真: {photo} / GPS: {gps}', {
                        'photo': _captureStatusLabel(item.photoStatus),
                        'gps': _captureStatusLabel(item.gpsStatus),
                      })),
                    if (item.storagePath.isEmpty)
                      SizedBox(height: 180,
                        child: Center(child: Text(SkoLanguageController.tr('写真未登録・送信失敗')))),
                    if (repository != null && item.storagePath.isNotEmpty)
                      FutureBuilder<String>(
                        key: ValueKey('${item.storageBucket}:${item.storagePath}'),
                        future:
                            repository.attendanceEvidenceUrl(item.storagePath, bucket: item.storageBucket),
                        builder: (context, snapshot) {
                          final url = snapshot.data;
                          if (url == null) {
                            return const SizedBox(
                              height: 180,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return InteractiveViewer(
                            minScale: 1,
                            maxScale: 5,
                            child: Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DailyReportPrintPreviewPage extends StatefulWidget {
  const DailyReportPrintPreviewPage({super.key, required this.date,
    required this.siteName, required this.workers, required this.workDescription,
    required this.report, this.evidence = const []});

  final DateTime date;
  final String siteName;
  final List<DailyReportWorkerDraft> workers;
  final String workDescription;
  final DailyReportRecord? report;
  final List<DailyReportEvidenceRecord> evidence;

  @override
  State<DailyReportPrintPreviewPage> createState() => _DailyReportPrintPreviewPageState();
}

class _DailyReportPrintPreviewPageState extends State<DailyReportPrintPreviewPage> {
  final _pdfBytes = PdfBytesCache();
  String? _fingerprint;

  Future<List<DailyReportPdfEvidence>> _loadEvidence() async {
    final repository = DailyReportRepository.maybeCreate();
    if (repository == null) {
      return [for (final record in widget.evidence)
        DailyReportPdfEvidence(record: record, downloadFailed: record.storagePath.isNotEmpty)];
    }
    return repository.loadPdfEvidence(widget.evidence);
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final fingerprint = DailyReportPdfService.fingerprint(date: widget.date,
      siteName: widget.siteName, workers: widget.workers,
      workDescription: widget.workDescription, report: widget.report,
      evidence: [for (final record in widget.evidence) DailyReportPdfEvidence(record: record)]);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _pdfBytes.invalidate();
    }
    return Scaffold(
      appBar: AppBar(title: Text(SkoLanguageController.tr('日報 A4プレビュー')),
        actions: const [SkoNotificationBell()]),
      body: PdfPreview(initialPageFormat: PdfPageFormat.a4,
        canChangePageFormat: false, canChangeOrientation: false,
        allowPrinting: true, allowSharing: true,
        pdfFileName: '${widget.date.toIso8601String().substring(0, 10)}_日報.pdf',
        build: (_) => _pdfBytes.get(() async => DailyReportPdfService.buildPdf(
          date: widget.date, siteName: widget.siteName, workers: widget.workers,
          workDescription: widget.workDescription, report: widget.report,
          evidence: await _loadEvidence()))),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(SkoLanguageController.tr('再読み込み')),
            ),
          ],
        ),
      ),
    );
  }
}

String _captureStatusLabel(String? status) => SkoLanguageController.tr(switch (status) {
  'acquired' || 'uploaded' => '登録済み',
  'upload_failed' => '送信失敗',
  'failed' => '取得失敗',
  _ => '未登録',
});
