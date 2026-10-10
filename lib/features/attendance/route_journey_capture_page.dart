import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../international/language_controller.dart';
import 'attendance_capture_metadata_service.dart';
import 'gps_photo_capture_controller.dart';
import 'gps_photo_capture_result.dart';
import 'route_journey_capture_draft.dart';
import 'route_journey_capture_repository.dart';

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

class _RepositoryAccess implements RouteJourneyCaptureAccess {
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
  });
  final RouteJourneyCaptureAccess? access;
  final String sourceId;
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
  String? _origin, _stopId, _error;
  bool _loading = false, _busy = false, _loadFailed = false;
  int _generation = 0;
  bool _left = false;
  Map? get _openVisit {
    final visits = _workspace?['visits'];
    if (visits is! List) return null;
    return visits
        .whereType<Map>()
        .where((row) => row['end_capture_id'] == null)
        .singleOrNull;
  }

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
      var workspace = await repository.workspace(
        pending?.sourceId ?? widget.sourceId,
      );
      if (!_active(generation)) return;
      _checkActor();
      pending ??= await repository.loadPending(
        workspace['company_id'] as String,
      );
      if (!_active(generation)) return;
      _checkActor();
      if (pending != null && pending.userId != _actor) {
        throw StateError('保留中の本人が一致しません');
      }
      setState(() => _pending = pending);
      if (pending != null &&
          pending.sourceId != workspace['source_clock_in_id']) {
        workspace = await repository.workspace(pending.sourceId);
        if (!_active(generation)) return;
        _checkActor();
      }
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
      setState(() {
        _workspace = workspace;
        _origin = pending?.originKind ?? workspace['origin_kind']?.toString();
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
    if (_busy || _loading || _loadFailed || _left) return;
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
        final isMove = _visitsEnabled && _openVisit != null;
        if (isMove && (_openVisit!['route_stop_id'] is! String ||
            (_openVisit!['route_stop_id'] as String).isEmpty ||
            _openVisit!['start_capture_id'] is! String ||
            (_openVisit!['start_capture_id'] as String).isEmpty ||
            _openVisit!['ended_at'] != null ||
            _openVisit!['end_capture_id'] != null)) {
          throw StateError('移動対象の現場記録を確認できません');
        }
        if (isMove) {
          draft = RouteJourneyCaptureDraft(
            userId: _actor!,
            companyId: captureContext.companyId,
            sourceId: captureContext.sourceClockInId!,
            stopId: _openVisit!['route_stop_id'] as String,
            originKind: origin,
            visitKind: 'end',
            startCaptureId: _openVisit!['start_capture_id']?.toString(),
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

  String _visitTime(Object? raw) {
    final time = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (time == null) return SkoLanguageController.tr('時刻不明');
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final workspace = _workspace;
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
          title: Text(SkoLanguageController.tr('途中現場のGPS＋写真')),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    SkoLanguageController.tr(
                      '出勤→現場→現場→退勤の行程です。会社出勤後の移動か直行直帰かを選び、実際に到着した現場を撮影します。',
                    ),
                  ),
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
                  if (_pending == null && enabled) ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      emptySelectionAllowed: true,
                      selected: _origin == null ? {} : {_origin!},
                      segments: [
                        ButtonSegment(
                          value: 'company',
                          label: Text(SkoLanguageController.tr('会社出勤後に現場へ')),
                        ),
                        ButtonSegment(
                          value: 'direct',
                          label: Text(SkoLanguageController.tr('直行直帰')),
                        ),
                      ],
                      onSelectionChanged:
                          _busy || workspace?['origin_kind'] != null
                          ? null
                          : (values) => setState(
                              () => _origin = values.isEmpty
                                  ? null
                                  : values.single,
                            ),
                    ),
                    const SizedBox(height: 12),
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
                          DropdownMenuItem(
                            value: stop['id'] as String,
                            child: Text(
                              '${stop['stop_order']}. ${stop['label']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy || _openVisit != null
                          ? null
                          : (value) => setState(() => _stopId = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_visitsEnabled && _pending == null &&
                      workspace?['archived'] != true) ...[
                    // A shift starts with arrival enabled. After arrival,
                    // only the move/leave action is enabled for this visit.
                    FilledButton.icon(
                      onPressed: !_busy && !_loading && !_loadFailed &&
                              enabled && _openVisit == null &&
                              _origin != null && _stopId != null
                          ? _captureOrRetry
                          : null,
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(SkoLanguageController.tr('現場到着')),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: !_busy && !_loading && !_loadFailed &&
                              enabled && _openVisit != null &&
                              _origin != null &&
                              _openVisit!['route_stop_id'] is String &&
                              (_openVisit!['route_stop_id'] as String).isNotEmpty &&
                              _openVisit!['start_capture_id'] is String &&
                              (_openVisit!['start_capture_id'] as String).isNotEmpty
                          ? _captureOrRetry
                          : null,
                      icon: const Icon(Icons.directions_walk_outlined),
                      label: Text(SkoLanguageController.tr('現場移動')),
                    ),
                  ] else if (workspace?['archived'] != true || _pending != null)
                    FilledButton.icon(
                      onPressed: _busy || _loading || _loadFailed ||
                              (_pending == null &&
                                  (!enabled || _origin == null || _stopId == null))
                          ? null
                          : _captureOrRetry,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(SkoLanguageController.tr(
                        _pending != null
                            ? '同じ途中現場記録で再確認'
                            : 'この現場を撮影して記録',
                      )),
                    ),
                  if (_visitsEnabled) ...[
                    const SizedBox(height: 16),
                    Text(
                      SkoLanguageController.tr(
                        '現場の終了と退勤は別です。最後の現場を終了した後、ホームから退勤してください。',
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
