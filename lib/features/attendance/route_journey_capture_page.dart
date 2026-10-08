import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../international/language_controller.dart';
import 'attendance_capture_metadata_service.dart';
import 'gps_photo_capture_controller.dart';
import 'gps_photo_capture_result.dart';
import 'route_journey_capture_draft.dart';
import 'route_journey_capture_repository.dart';

class RouteJourneyCapturePage extends StatefulWidget {
  const RouteJourneyCapturePage({super.key, required this.sourceId});
  final String sourceId;
  @override State<RouteJourneyCapturePage> createState() => _RouteJourneyCapturePageState();
}
class _RouteJourneyCapturePageState extends State<RouteJourneyCapturePage> {
  final _repository = RouteJourneyCaptureRepository.maybeCreate();
  final _picker = ImagePicker();
  final _metadata = const AttendanceCaptureMetadataService();
  Map<String, dynamic>? _workspace, _saved;
  RouteJourneyCaptureDraft? _pending;
  String? _origin, _stopId, _error;
  bool _loading = true, _busy = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError('途中現場の記録を利用できません');
      final allPending = await repository.allPending();
      final matches = allPending.where((draft) => draft.sourceId == widget.sourceId).toList();
      var pending = matches.isEmpty ? null : matches.single;
      if (mounted) setState(() => _pending = pending);
      var workspace = await repository.workspace(pending?.sourceId ?? widget.sourceId);
      pending ??= await repository.loadPending(workspace['company_id'] as String);
      if (mounted) setState(() => _pending = pending);
      if (pending != null && pending.sourceId != workspace['source_clock_in_id']) {
        workspace = await repository.workspace(pending.sourceId);
      }
      if (!mounted) return;
      setState(() {
        _workspace = workspace; _origin = pending?.originKind ?? workspace['origin_kind']?.toString();
        _stopId = pending?.stopId; _loading = false; _error = null;
      });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }
  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw StateError('位置情報サービスが無効です');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw StateError('位置情報が許可されていません');
    return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
      .timeout(const Duration(seconds: 15));
  }
  Future<CaptureDecision> _prompt(CaptureFailure failure) async {
    if (!mounted) return CaptureDecision.confirm;
    final message = switch (failure) {
      CaptureFailure.camera => '写真を取得できませんでした。撮り直すか、未取得の状態を記録してください。',
      CaptureFailure.gps => 'GPSを取得できませんでした。撮り直すか、取得失敗を記録してください。',
      CaptureFailure.upload => '写真を送信できませんでした。撮り直すか、送信失敗を記録してください。',
    };
    return await showDialog<CaptureDecision>(context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(title: Text(SkoLanguageController.tr('途中現場の撮影確認')),
        content: Text(SkoLanguageController.tr(message)), actions: [
          TextButton(onPressed: () => Navigator.pop(context, CaptureDecision.retake), child: Text(SkoLanguageController.tr('撮り直す'))),
          FilledButton(onPressed: () => Navigator.pop(context, CaptureDecision.confirm), child: Text(SkoLanguageController.tr('確認'))),
        ])) ?? CaptureDecision.confirm;
  }
  Future<void> _captureOrRetry() async {
    if (_busy) return;
    final repository = _repository;
    if (repository == null) return;
    setState(() => _busy = true);
    try {
      var draft = _pending;
      if (draft == null) {
        final workspace = _workspace;
        if (workspace == null || workspace['enabled'] != true || workspace['is_open'] != true || _stopId == null || _origin == null) return;
        final captureContext = CaptureShiftContext(companyId: workspace['company_id'] as String,
          workDate: workspace['work_date'] as String, requestedMethod: 'location_photo',
          sourceClockInId: workspace['source_clock_in_id'] as String, routeId: workspace['route_assignment_id'] as String);
        final capture = await GpsPhotoCaptureController(camera: () async {
          final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
          if (image == null) return null;
          final observed = DateTime.now();
          return CapturedPhoto(bytes: await image.readAsBytes(), observedAt: observed,
            capturedAt: await _metadata.readPhotoCapturedAt(image.path));
        }, sampleGps: () async {
          final position = await _position();
          return CapturedGpsSample(latitude: position.latitude, longitude: position.longitude,
            sampledAt: position.timestamp, accuracyM: position.accuracy,
            address: await _metadata.reverseGeocodeCapturedLocation(latitude: position.latitude, longitude: position.longitude));
        }, upload: (photo, shift) => repository.upload(photo, shift, workspace['worker_id'] as String),
          prompt: _prompt, now: DateTime.now).capture(captureContext);
        draft = RouteJourneyCaptureDraft(userId: repository.userId, companyId: captureContext.companyId,
          sourceId: captureContext.sourceClockInId!, stopId: _stopId!, originKind: _origin!, payload: {
            ...capture.insertMetadata, 'latitude': capture.gps?.latitude, 'longitude': capture.gps?.longitude,
            'accuracy_m': capture.gps?.accuracyM, 'photo_storage_path': capture.storagePath,
            'attempted_at': capture.attemptedAt.toUtc().toIso8601String(),
          });
        if (mounted) setState(() => _pending = draft);
      }
      final saved = await repository.submit(draft);
      if (!mounted) return;
      setState(() { _pending = null; _saved = saved; _error = null; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(SkoLanguageController.tr('途中現場の取得状態を記録しました'))));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '${SkoLanguageController.tr('登録結果は未確認です。同じ記録で再確認してください')}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override Widget build(BuildContext context) {
    final workspace = _workspace;
    final stops = workspace?['stops'] is List ? (workspace!['stops'] as List).whereType<Map>().toList() : <Map>[];
    final enabled = workspace?['enabled'] == true && workspace?['is_open'] == true;
    return Scaffold(appBar: AppBar(title: Text(SkoLanguageController.tr('途中現場のGPS＋写真'))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
        Text(SkoLanguageController.tr('出勤→現場→現場→退勤の行程です。会社出勤後の移動か直行直帰かを選び、実際に到着した現場を撮影します。')),
        if (workspace != null) Text('${SkoLanguageController.tr('勤務日')}: ${workspace['work_date']}'),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!)),
        if (_pending != null) Text(SkoLanguageController.tr('保留中の対象・写真・取得状態は固定されています。新しい記録を作らず同じUUIDを照会します。')),
        if (!enabled && _pending == null) Text(SkoLanguageController.tr('途中現場の記録は利用できません。機能設定または対象勤務を確認してください。')),
        if (_pending == null && enabled) ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(emptySelectionAllowed: true, selected: _origin == null ? {} : {_origin!}, segments: [
            ButtonSegment(value: 'company', label: Text(SkoLanguageController.tr('会社出勤後に現場へ'))),
            ButtonSegment(value: 'direct', label: Text(SkoLanguageController.tr('直行直帰'))),
          ], onSelectionChanged: _busy || workspace?['origin_kind'] != null ? null : (values) => setState(() => _origin = values.isEmpty ? null : values.single)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _stopId, isExpanded: true,
            decoration: InputDecoration(labelText: SkoLanguageController.tr('到着した現場（登録済みルート）')),
            items: [for (final stop in stops) DropdownMenuItem(value: stop['id'] as String, child: Text('${stop['stop_order']}. ${stop['label']}', overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : (value) => setState(() => _stopId = value)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy || (_pending == null && (!enabled || _origin == null || _stopId == null)) ? null : _captureOrRetry,
          icon: const Icon(Icons.camera_alt_outlined), label: Text(SkoLanguageController.tr(_pending == null ? 'この現場を撮影して記録' : '同じ途中現場記録で再確認'))),
        if (_saved != null) ...[
          const SizedBox(height: 16), Text('${_saved!['stop_label']} / ${_saved!['work_date']}'),
          Text('${SkoLanguageController.tr('撮影住所')}: ${(_saved!['payload'] as Map)['captured_address'] ?? SkoLanguageController.tr('未取得')}'),
          Text('${SkoLanguageController.tr('写真の保存状態')}: ${(_saved!['payload'] as Map)['photo_capture_status']}'),
          Text('${SkoLanguageController.tr('GPSの取得状態')}: ${(_saved!['payload'] as Map)['gps_capture_status']}'),
        ],
      ]));
  }
}
