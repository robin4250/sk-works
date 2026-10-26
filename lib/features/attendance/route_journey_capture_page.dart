import '../../widgets/input_step_heading.dart';
import 'saved_capture_photo_status.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../international/language_controller.dart';
import '../help/floating_help_controller.dart';
import '../daily_reports/daily_report_page.dart';
import '../daily_reports/route_visit_report_context.dart';
import 'attendance_capture_metadata_service.dart';
import 'gps_photo_capture_controller.dart';
import 'gps_photo_capture_result.dart';
import 'route_journey_capture_draft.dart';
import 'route_journey_capture_repository.dart';
import 'route_journey_visit_progress.dart';

abstract class RouteJourneyCaptureAccess {
  String get userId;
  Future<List<RouteJourneyCaptureDraft>> allPending();
  Future<Map<String, dynamic>> workspace(String sourceId);
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId);
  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft draft);
  Future<String> upload(
    CapturedPhoto photo,
    CaptureShiftContext context,
    String workerId,
  );
}

abstract class RouteVisitReportAccess {
  Future<List<RouteVisitReportPending>> allPendingReports();
  Future<RouteVisitReportPending> chooseReport(
    RouteVisitReportPending pending,
    String choice,
  );
  Future<void> finishReport(RouteVisitReportPending pending);
}

class _RepositoryAccess
    implements RouteJourneyCaptureAccess, RouteVisitReportAccess {
  final _repository = RouteJourneyCaptureRepository.maybeCreate();
  RouteJourneyCaptureRepository get repository =>
      _repository ?? (throw StateError('途中現場の記録を利用できません'));
  @override
  String get userId => repository.userId;
  @override
  Future<List<RouteJourneyCaptureDraft>> allPending() =>
      repository.allPending();
  @override
  Future<Map<String, dynamic>> workspace(String sourceId) =>
      repository.workspace(sourceId);
  @override
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId) =>
      repository.loadPending(companyId);
  @override
  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft draft) =>
      repository.submit(draft);
  @override
  Future<List<RouteVisitReportPending>> allPendingReports() =>
      repository.allPendingReports();
  @override
  Future<RouteVisitReportPending> chooseReport(
    RouteVisitReportPending pending,
    String choice,
  ) => repository.chooseReport(pending, choice);
  @override
  Future<void> finishReport(RouteVisitReportPending pending) =>
      repository.finishReport(pending);
  @override
  Future<String> upload(
    CapturedPhoto photo,
    CaptureShiftContext context,
    String workerId,
  ) => repository.upload(photo, context, workerId);
}

class RouteJourneyCapturePage extends StatefulWidget {
  const RouteJourneyCapturePage({
    super.key,
    required this.sourceId,
    this.access,
    this.initialAction,
  });
  final RouteJourneyCaptureAccess? access;
  final String sourceId;

  /// Highlights the requested home action without recording it automatically.
  final String? initialAction;
  @override
  State<RouteJourneyCapturePage> createState() =>
      _RouteJourneyCapturePageState();
}

class _RouteJourneyCapturePageState extends State<RouteJourneyCapturePage> {
  late final _repository = widget.access ?? _RepositoryAccess();
  final _picker = ImagePicker();
  final _metadata = const AttendanceCaptureMetadataService();
  Map<String, dynamic>? _workspace, _saved;
  RouteJourneyCaptureDraft? _pending;
  RouteVisitReportPending? _pendingReport;
  String? _origin, _stopId, _error;
  bool _loading = false, _busy = false, _loadFailed = false;
  int _generation = 0;
  bool _left = false, _reportBusy = false;
  RouteJourneyVisitProgress? get _progress => _workspace == null
      ? null
      : RouteJourneyVisitProgress.fromWorkspace(_workspace!, widget.sourceId);
  Map? get _openVisit => _progress?.openVisit;

  bool get _visitsEnabled => _workspace?['visit_contract_version'] == 1;

  String? _actor;
  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _active(int generation) =>
      mounted && !_left && generation == _generation;
  void _checkActor() {
    if (_actor == null || _actor != _repository.userId) {
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
  }

  Future<void> _load() async {
    if (_loading || _left) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      final repository = _repository;
      _actor ??= repository.userId;
      _checkActor();
      final allPending = await repository.allPending();
      if (!_active(generation)) return;
      _checkActor();
      final matches = allPending
          .where((draft) => draft.sourceId == widget.sourceId)
          .toList();
      // A failed read must not discard the already recovered fixed command.
      var pending = _pending ?? (matches.isEmpty ? null : matches.single);
      if (pending != null && pending.userId != _actor) {
        throw StateError('保留中の本人が一致しません');
      }
      setState(() => _pending = pending);
      final workspace = await repository.workspace(
        pending?.sourceId ?? widget.sourceId,
      );
      if (!_active(generation)) return;
      _checkActor();
      if (pending == null) {
        final companyPending = await repository.loadPending(
          workspace['company_id'] as String,
        );
        // Recovery is selected by source on home. A later shift from the same
        // company must never replace the closed visit being resumed here.
        if (companyPending?.sourceId == widget.sourceId) {
          pending = companyPending;
        }
      }
      if (!_active(generation)) return;
      _checkActor();
      if (pending != null && pending.userId != _actor) {
        throw StateError('保留中の本人が一致しません');
      }
      setState(() => _pending = pending);
      if (workspace['visit_contract_version'] != null) {
        final visits = workspace['visits'];
        if (workspace['visit_contract_version'] != 1 ||
            visits is! List ||
            visits.any(
              (row) =>
                  row is! Map ||
                  row['start_capture_id'] is! String ||
                  row['route_stop_id'] is! String ||
                  row['work_date'] != workspace['work_date'] ||
                  DateTime.tryParse(row['started_at']?.toString() ?? '') ==
                      null ||
                  !row.containsKey('end_capture_id') ||
                  !row.containsKey('ended_at') ||
                  ((row['end_capture_id'] == null) !=
                      (row['ended_at'] == null)) ||
                  (row['ended_at'] != null &&
                      DateTime.tryParse(row['ended_at'].toString()) == null),
            ) ||
            visits.where((row) => row['end_capture_id'] == null).length > 1) {
          throw StateError('訪問履歴を確認できません');
        }
      }
      final reports = repository is RouteVisitReportAccess
          ? await (repository as RouteVisitReportAccess).allPendingReports()
          : <RouteVisitReportPending>[];
      if (!_active(generation)) return;
      _checkActor();
      final reportMatches = reports
          .where((row) => row.sourceId == widget.sourceId)
          .toList();
      setState(() {
        _pendingReport = reportMatches.isEmpty ? null : reportMatches.first;
        _workspace = workspace;
        // Preserve saved command/origin contracts after removing the UI choice.
        _origin =
            pending?.originKind ??
            workspace['origin_kind']?.toString() ??
            'company';
        _stopId = pending?.stopId ?? _openVisit?['route_stop_id']?.toString();
      });
    } catch (_) {
      if (_active(generation)) {
        setState(() {
          _workspace = null;
          _loadFailed = true;
          _error = SkoLanguageController.isEnglish
              ? 'Could not load the shift. Retry to check the same record.'
              : '勤務情報を読み込めませんでした。再読み込みで同じ記録を確認してください。';
        });
      }
    } finally {
      if (_active(generation)) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _left = true;
    _generation++;
    super.dispose();
  }

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('位置情報サービスが無効です');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('位置情報が許可されていません');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
  }

  Future<CaptureDecision> _prompt(CaptureFailure failure) async {
    if (!mounted || _left) return CaptureDecision.confirm;
    try {
      _checkActor();
    } catch (_) {
      return CaptureDecision.confirm;
    }
    final message = switch (failure) {
      CaptureFailure.camera => '写真を取得できませんでした。撮り直すか、未取得の状態を記録してください。',
      CaptureFailure.gps => 'GPSを取得できませんでした。撮り直すか、取得失敗を記録してください。',
      CaptureFailure.upload => '写真を送信できませんでした。撮り直すか、送信失敗を記録してください。',
    };
    return await showDialog<CaptureDecision>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(SkoLanguageController.tr('途中現場の撮影確認')),
            content: Text(SkoLanguageController.tr(message)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, CaptureDecision.retake),
                child: Text(SkoLanguageController.tr('撮り直す')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, CaptureDecision.confirm),
                child: Text(SkoLanguageController.tr('確認')),
              ),
            ],
          ),
        ) ??
        CaptureDecision.confirm;
  }

  Future<void> _captureOrRetry() async {
    if (_busy || _loading || _loadFailed || _left || _pendingReport != null) {
      return;
    }
    final repository = _repository;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      _checkActor();
      var draft = _pending;
      if (draft == null) {
        final workspace = _workspace;
        if (workspace == null ||
            workspace['enabled'] != true ||
            workspace['is_open'] != true ||
            _stopId == null ||
            _origin == null) {
          return;
        }
        final captureContext = CaptureShiftContext(
          companyId: workspace['company_id'] as String,
          workDate: workspace['work_date'] as String,
          requestedMethod: 'location_photo',
          sourceClockInId: workspace['source_clock_in_id'] as String,
          routeId: workspace['route_assignment_id'] as String,
        );
        final stopId = _stopId!;
        final origin = _origin!;
        // Leaving a visited site records the action time only. Do not
        // request another camera shot or GPS sample for the move action.
        if (_visitsEnabled) {
          final fresh = await repository.workspace(widget.sourceId);
          if (!_active(generation)) return;
          _checkActor();
          final progress = RouteJourneyVisitProgress.fromWorkspace(
            fresh,
            widget.sourceId,
          );
          final previousOpen = _openVisit;
          final freshOpen = progress?.openVisit;
          if (progress == null ||
              fresh['company_id'] != workspace['company_id'] ||
              fresh['worker_id'] != workspace['worker_id'] ||
              fresh['work_date'] != workspace['work_date'] ||
              fresh['route_assignment_id'] !=
                  workspace['route_assignment_id'] ||
              (previousOpen == null &&
                  (!progress.canArrive ||
                      !progress.remainingStopIds.contains(stopId))) ||
              (previousOpen != null &&
                  (freshOpen == null ||
                      freshOpen['start_capture_id'] !=
                          previousOpen['start_capture_id'] ||
                      freshOpen['route_stop_id'] != stopId))) {
            setState(() {
              _workspace = fresh;
              _stopId = freshOpen?['route_stop_id']?.toString();
            });
            return;
          }
          setState(() => _workspace = fresh);
        }
        final isMove = _visitsEnabled && _openVisit != null;
        if (isMove &&
            (_openVisit!['route_stop_id'] is! String ||
                (_openVisit!['route_stop_id'] as String).isEmpty ||
                _openVisit!['start_capture_id'] is! String ||
                (_openVisit!['start_capture_id'] as String).isEmpty ||
                _openVisit!['ended_at'] != null ||
                _openVisit!['end_capture_id'] != null ||
                _openVisit!['route_stop_id'] != stopId)) {
          throw StateError('移動対象の現場記録を確認できません');
        }
        final isManual = workspace['verification_mode'] == 'manual';
        if (isMove || isManual) {
          draft = RouteJourneyCaptureDraft(
            userId: _actor!,
            companyId: captureContext.companyId,
            sourceId: captureContext.sourceClockInId!,
            stopId: isMove ? _openVisit!['route_stop_id'] as String : stopId,
            originKind: origin,
            visitKind: isMove ? 'end' : 'start',
            startCaptureId: isMove
                ? _openVisit!['start_capture_id']?.toString()
                : null,
            payload: {
              'capture_contract_version': 1,
              'gps_capture_status': 'missing',
              'photo_capture_status': 'missing',
              'gps_captured_at': null,
              'photo_captured_at': null,
              'photo_observed_at': null,
              'captured_address': null,
              'latitude': null,
              'longitude': null,
              'accuracy_m': null,
              'photo_storage_path': null,
              'attempted_at': DateTime.now().toUtc().toIso8601String(),
            },
          );
        } else {
          final capture = await GpsPhotoCaptureController(
            camera: () async {
              if (!_active(generation)) throw StateError('Closed capture');
              _checkActor();
              final image = await _picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 85,
                maxWidth: 2200,
              );
              if (image == null) return null;
              final observed = DateTime.now();
              return CapturedPhoto(
                bytes: await image.readAsBytes(),
                observedAt: observed,
                capturedAt: await _metadata.readPhotoCapturedAt(image.path),
              );
            },
            sampleGps: () async {
              if (!_active(generation)) throw StateError('Closed capture');
              _checkActor();
              final position = await _position();
              return CapturedGpsSample(
                latitude: position.latitude,
                longitude: position.longitude,
                sampledAt: position.timestamp,
                accuracyM: position.accuracy,
                address: await _metadata.reverseGeocodeCapturedLocation(
                  latitude: position.latitude,
                  longitude: position.longitude,
                ),
              );
            },
            upload: (photo, shift) {
              if (!_active(generation)) throw StateError('Closed capture');
              _checkActor();
              return repository.upload(
                photo,
                shift,
                workspace['worker_id'] as String,
              );
            },
            prompt: _prompt,
            now: DateTime.now,
          ).capture(captureContext);
          if (!_active(generation)) return;
          _checkActor();
          draft = RouteJourneyCaptureDraft(
            userId: _actor!,
            companyId: captureContext.companyId,
            sourceId: captureContext.sourceClockInId!,
            stopId: stopId,
            originKind: origin,
            visitKind: _visitsEnabled
                ? (_openVisit == null ? 'start' : 'end')
                : null,
            startCaptureId: _openVisit?['start_capture_id']?.toString(),
            payload: {
              ...capture.insertMetadata,
              'latitude': capture.gps?.latitude,
              'longitude': capture.gps?.longitude,
              'accuracy_m': capture.gps?.accuracyM,
              'photo_storage_path': capture.storagePath,
              'attempted_at': capture.attemptedAt.toUtc().toIso8601String(),
            },
          );
        }
        if (mounted) setState(() => _pending = draft);
      }
      if (!_active(generation)) return;
      _checkActor();
      final saved = await repository.submit(draft);
      if (!_active(generation)) return;
      _checkActor();
      setState(() {
        _pending = null;
        _saved = saved;
        _error = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SkoLanguageController.tr(
              saved['archived'] == true
                  ? '管理変更前の記録を確認しました'
                  : '途中現場の取得状態を記録しました',
            ),
          ),
        ),
      );
      await _load();
      if (draft.visitKind == 'end' && _pendingReport != null && mounted) {
        await _resumeReport();
      } else if (draft.visitKind == 'start' &&
          mounted &&
          saved['archived'] != true &&
          !_loadFailed) {
        if (_progress?.isFinalVisit == true) {
          Navigator.of(context).pop(true);
        } else {
          await _returnHome('作業終了して次の現場に向かう時に現場移動ボタン押してください');
        }
      }
    } catch (error) {
      if (_active(generation)) {
        setState(
          () => _error =
              '${SkoLanguageController.tr('登録結果は未確認です。同じ記録で再確認してください')}: $error',
        );
      }
    } finally {
      if (mounted && !_left) setState(() => _busy = false);
    }
  }

  Future<void> _resumeReport() async {
    final access = _repository;
    final initialPending = _pendingReport;
    if (initialPending == null ||
        access is! RouteVisitReportAccess ||
        _left ||
        _reportBusy) {
      return;
    }
    final reportAccess = access as RouteVisitReportAccess;
    RouteVisitReportPending pending = initialPending;
    setState(() => _reportBusy = true);
    try {
      _checkActor();
      if (pending.choice == 'undecided') {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(SkoLanguageController.tr('この現場の日報')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const InputStepHeading(number: '④', title: '日報を作成する／しないを選択'),
              Text(SkoLanguageController.tr('この現場の日報を作成しますか？')),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'skip'),
                child: Text(SkoLanguageController.tr('作成しない')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, 'create'),
                child: Text(SkoLanguageController.tr('作成する')),
              ),
            ],
          ),
        );
        if (!mounted || _left || choice == null) return;
        _checkActor();
        pending = pending.withChoice(choice);
        if (!mounted || _left) return;
        _checkActor();
        setState(() => _pendingReport = pending);
      }
      pending = await reportAccess.chooseReport(pending, pending.choice);
      if (!mounted || _left) return;
      _checkActor();
      setState(() => _pendingReport = pending);
      if (pending.choice == 'create') {
        final report = pending;
        final workspace = _workspace!;
        final stops = (workspace['stops'] as List).whereType<Map>();
        final stop = stops
            .where((row) => row['id'] == report.stopId)
            .firstOrNull;
        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => DailyReportPage(
              initialDate: DateTime.parse(report.workDate),
              initialSiteId: stop?['site_id']?.toString(),
              routeVisitContext: RouteVisitReportContext(
                sourceClockInId: report.sourceId,
                routeAssignmentId: workspace['route_assignment_id'] as String,
                routeStopId: report.stopId,
                startCaptureId: report.startCaptureId,
                endCaptureId: report.endCaptureId,
              ),
            ),
          ),
        );
        if (!mounted || _left) return;
        _checkActor();
        if (completed != true) return;
      }
      await reportAccess.finishReport(pending);
      if (!mounted || _left) return;
      _checkActor();
      await _load();
      if (!_loadFailed && _pendingReport == null && mounted) {
        if (_workspace?['is_open'] == true &&
            _progress?.remainingStopIds.isNotEmpty == true) {
          await _returnHome('次の現場に到着したら現場到着ボタンを押してください');
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      if (mounted && !_left) {
        setState(
          () => _error = '${SkoLanguageController.tr('現場日報を再開してください')}: $error',
        );
      }
    } finally {
      if (mounted && !_left) setState(() => _reportBusy = false);
    }
  }

  Future<void> _returnHome(String message) async {
    if (!mounted || _left) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Text(SkoLanguageController.tr(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(SkoLanguageController.tr('確認')),
          ),
        ],
      ),
    );
    if (!mounted || _left) return;
    _checkActor();
    Navigator.of(context).pop(true);
  }

  String _visitTime(Object? raw) {
    final time = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (time == null) return SkoLanguageController.tr('時刻不明');
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    FloatingHelpController.setContext(featureKey: 'attendance');
    final workspace = _workspace;
    final savedForStop = _saved != null && _saved!['route_stop_id'] == _stopId;
    final photoSaved = _pending == null && savedForStop &&
        savedCapturePhotoRegistered(_saved);
    final photoMode = workspace?['verification_mode'] == 'location_photo';
    final stops = workspace?['stops'] is List
        ? (workspace!['stops'] as List).whereType<Map>().toList()
        : <Map>[];
    final enabled =
        workspace?['enabled'] == true && workspace?['is_open'] == true;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _left = true;
          _generation++;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight,
          title: Text(SkoLanguageController.tr('現場到着・現場移動')),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(SkoLanguageController.tr('作業する現場を選び、現場到着のボタンを押してください')),
                  if (widget.initialAction != null)
                    Text(
                      SkoLanguageController.tr(
                        widget.initialAction == 'move'
                            ? '現在の現場から移動する時刻を記録します。'
                            : '到着した現場を選んで記録してください。',
                      ),
                    ),
                  if (workspace?['verification_mode'] == 'manual')
                    Text(SkoLanguageController.tr('手動出勤では到着・移動の時刻のみ記録します。')),
                  if (workspace != null)
                    Text(
                      '${SkoLanguageController.tr('勤務日')}: ${workspace['work_date']}',
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_error!),
                    ),
                  if (_loadFailed)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(SkoLanguageController.tr('再読み込み')),
                    ),
                  if (_pending != null)
                    Text(
                      SkoLanguageController.tr(
                        '保留中の対象・写真・取得状態は固定されています。新しい記録を作らず同じUUIDを照会します。',
                      ),
                    ),
                  if (workspace?['archived'] == true)
                    Text(
                      SkoLanguageController.tr(
                        'この勤務は管理変更されています。変更前の記録は保持されています。新しい開始・終了は登録できません。',
                      ),
                    ),
                  if (!enabled &&
                      _pending == null &&
                      workspace?['archived'] != true)
                    Text(
                      SkoLanguageController.tr(
                        '途中現場の記録は利用できません。機能設定または対象勤務を確認してください。',
                      ),
                    ),
                  if (_pending == null &&
                      _pendingReport == null &&
                      enabled) ...[
                    const SizedBox(height: 12),
                    const InputStepHeading(number: '①', title: '途中現場を確認'),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_generation),
                      initialValue: _stopId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: SkoLanguageController.tr(
                          _visitsEnabled
                              ? '作業する現場（登録済みルート）'
                              : '到着した現場（登録済みルート）',
                        ),
                      ),
                      items: [
                        for (final stop in stops)
                          if (!_visitsEnabled ||
                              _openVisit != null ||
                              _progress?.remainingStopIds.contains(
                                    stop['id'],
                                  ) ==
                                  true)
                            DropdownMenuItem(
                              value: stop['id'] as String,
                              child: Text(
                                '${stop['stop_order']}. ${stop['label']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged:
                          _busy ||
                              _openVisit != null ||
                              (_visitsEnabled && _progress?.canArrive != true)
                          ? null
                          : (value) => setState(() => _stopId = value),
                    ),
                  ],
                  if (_pendingReport != null) ...[
                    const InputStepHeading(number: '④', title: 'この現場の日報を完了'),
                    const SizedBox(height: 16),
                    Text(
                      SkoLanguageController.tr(
                        'この訪問の日報が未完了です。作成または作成しないを確定してから次の現場へ進んでください。',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || _loading || _reportBusy
                          ? null
                          : _resumeReport,
                      icon: const Icon(Icons.description_outlined),
                      label: Text(SkoLanguageController.tr('現場日報を再開')),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_visitsEnabled &&
                      _pending == null &&
                      workspace?['archived'] != true) ...[
                    InputStepHeading(number: '②', title: '到着・写真を記録',
                      status: photoMode && photoSaved && _saved!['visit_kind'] == 'start'
                          ? '写真登録済み' : null,
                      complete: photoMode && photoSaved && _saved!['visit_kind'] == 'start'),
                    // A shift starts with arrival enabled. After arrival,
                    // only the move/leave action is enabled for this visit.
                    FilledButton.icon(
                      onPressed:
                          !_busy &&
                              !_loading &&
                              !_loadFailed &&
                              _pendingReport == null &&
                              enabled &&
                              _openVisit == null &&
                              _progress?.canArrive == true &&
                              _progress!.remainingStopIds.contains(_stopId) &&
                              _origin != null &&
                              _stopId != null
                          ? _captureOrRetry
                          : null,
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(SkoLanguageController.tr('現場到着')),
                    ),
                    const SizedBox(height: 8),
                    InputStepHeading(number: '③', title: _progress?.isFinalVisit == true
                      ? '最後の現場：ホームから退勤' : '作業終了後、次の現場へ移動'),
                    FilledButton.icon(
                      onPressed:
                          !_busy &&
                              !_loading &&
                              !_loadFailed &&
                              _pendingReport == null &&
                              enabled &&
                              _openVisit != null &&
                              _progress?.isFinalVisit != true &&
                              _origin != null &&
                              _openVisit!['route_stop_id'] is String &&
                              (_openVisit!['route_stop_id'] as String)
                                  .isNotEmpty &&
                              _openVisit!['start_capture_id'] is String &&
                              (_openVisit!['start_capture_id'] as String)
                                  .isNotEmpty &&
                              _openVisit!['route_stop_id'] == _stopId &&
                              _openVisit!['ended_at'] == null &&
                              _openVisit!['end_capture_id'] == null
                          ? _captureOrRetry
                          : null,
                      icon: const Icon(Icons.directions_walk_outlined),
                      label: Text(SkoLanguageController.tr('現場移動')),
                    ),
                  ] else if (workspace?['archived'] != true || _pending != null) ...[
                    InputStepHeading(number: '②', title: _pending != null
                      ? '同じ現場記録の保存状況を再確認' : '途中現場の写真・位置情報を記録',
                      status: !photoMode ? null : _pending != null ? '保存未確認'
                          : photoSaved ? '写真登録済み' : null,
                      complete: photoMode && photoSaved),
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              _loading ||
                              _loadFailed ||
                              _pendingReport != null ||
                              (_pending == null &&
                                  (!enabled ||
                                      _origin == null ||
                                      _stopId == null))
                          ? null
                          : _captureOrRetry,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        SkoLanguageController.tr(
                          _pending != null ? '同じ途中現場記録で再確認' : 'この現場を撮影して記録',
                        ),
                      ),
                    ),
                  ],
                  if (_visitsEnabled) ...[
                    const SizedBox(height: 16),
                    Text(
                      SkoLanguageController.tr(
                        '最後の現場に到着したらホームから退勤してください。退勤後に日報とサインを登録します。',
                      ),
                    ),
                    for (final visit
                        in (_workspace?['visits'] as List? ?? const [])
                            .whereType<Map>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(visit['stop_label']?.toString() ?? ''),
                        subtitle: Text(
                          '${_visitTime(visit['started_at'])} → ${visit['ended_at'] == null ? SkoLanguageController.tr('作業中') : _visitTime(visit['ended_at'])}',
                        ),
                      ),
                  ],
                  if (_saved != null) ...[
                    const SizedBox(height: 16),
                    Text('${_saved!['stop_label']} / ${_saved!['work_date']}'),
                    Text(
                      '${SkoLanguageController.tr('撮影住所')}: ${(_saved!['payload'] as Map)['captured_address'] ?? SkoLanguageController.tr('未取得')}',
                    ),
                    Text(
                      '${SkoLanguageController.tr('写真の保存状態')}: ${(_saved!['payload'] as Map)['photo_capture_status']}',
                    ),
                    Text(
                      '${SkoLanguageController.tr('GPSの取得状態')}: ${(_saved!['payload'] as Map)['gps_capture_status']}',
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

