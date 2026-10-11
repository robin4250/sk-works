import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../daily_reports/daily_report_page.dart';
import '../../international/language_controller.dart';
import '../notifications/notification_bell.dart';
import 'attendance_cloud_repository.dart';
import 'attendance_verification_repository.dart';
import 'attendance_shift_context.dart';
import 'gps_photo_capture_controller.dart';
import 'gps_photo_capture_result.dart';
import 'capture_verification_draft.dart';
import 'attendance_capture_metadata_service.dart';
import 'route_journey_capture_repository.dart';
import 'route_journey_capture_page.dart';
import 'group_checkout_dialog.dart';
import 'bulk_attendance_page.dart';
import 'gps_auto_attendance_service.dart';
import 'gps_auto_schedule_dialog.dart';

/// Today's explicit destination wins over a saved GPS schedule, including nulls.
({String? siteId, String? routeId}) resolveAttendanceClockInDestination({
  required Map<String, dynamic> selection,
  required Map<String, dynamic> gpsSchedule,
  String? selectedRouteId,
}) {
  String? id(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
  if (selection.isNotEmpty) {
    final site = id(selection['site_id']);
    return (siteId: site, routeId: site == null ? id(selection['route_assignment_id']) : null);
  }
  final route = id(selectedRouteId) ?? id(gpsSchedule['route_assignment_id']);
  return (siteId: route == null ? id(gpsSchedule['site_id']) : null, routeId: route);
}

class AttendanceDestinationSiteField extends StatelessWidget {
  const AttendanceDestinationSiteField({super.key, required this.siteId,
    required this.routeId, required this.sites, required this.locked,
    required this.onChanged});
  final String? siteId;
  final String? routeId;
  final List<Map<String, dynamic>> sites;
  final bool locked;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    key: ValueKey('site:$siteId'),
    initialValue: siteId,
    decoration: const InputDecoration(labelText: '現場',
      prefixIcon: Icon(Icons.business_outlined), border: OutlineInputBorder()),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('未登録（ルートで出勤）')),
      for (final site in sites) DropdownMenuItem<String?>(
        value: site['id']?.toString(), child: Text(site['name']?.toString() ?? '現場')),
    ],
    // A route's individual stops are selected after clock-in, at arrival.
    onChanged: locked || (routeId?.trim().isNotEmpty ?? false) ? null : onChanged,
  );
}

class AttendanceVerificationPage extends StatefulWidget {
  const AttendanceVerificationPage({
    super.key,
    this.initialEventType,
  });

  final String? initialEventType;

  @override
  State<AttendanceVerificationPage> createState() =>
      _AttendanceVerificationPageState();
}

class _AttendanceVerificationPageState
    extends State<AttendanceVerificationPage> {
  final _repository = AttendanceVerificationRepository.maybeCreate();
  final _bulkAttendanceRepository = AttendanceCloudRepository.maybeCreate();
  final _picker = ImagePicker();
  final _journeyRepository = RouteJourneyCaptureRepository.maybeCreate();
  List<AttendanceShiftContext> _journeyShifts = const [];
  List<String> _pendingJourneySourceIds = const [];
  final _captureMetadata = const AttendanceCaptureMetadataService();
  final _noteController = TextEditingController();

  List<Map<String, dynamic>> _workers = const [];
  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _recent = const [];
  List<AttendanceShiftContext> _openShifts = const [];
  AttendanceShiftContext? _shift;

  String _mode = 'none';
  String? _workerId;
  String? _siteId;
  late String _eventType;
  List<int> _gpsWeekdays = const [1, 2, 3, 4, 5];
  TimeOfDay _gpsTime = const TimeOfDay(hour: 8, minute: 0);

  String? _vehicleName;
  String? _vehicleId;
  String? _routeId;
  String? _routeName;

  bool _loading = true;
  bool _saving = false;
  CaptureVerificationDraft? _pendingCaptureDraft;
  Map<String, dynamic>? _savedCaptureVerification;
  bool get _editingLocked => _saving || _pendingCaptureDraft != null || _savedCaptureVerification != null;
  bool _canManageAttendance = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _eventType =
        widget.initialEventType == 'clock_out' ? 'clock_out' : 'clock_in';
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = 'Supabase接続が利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        repository.loadWorkers(),
        repository.loadSites(),
        repository.loadRecent(),
        repository.loadAttendanceSelectionWorkspace(),
        repository.loadHomeAttendanceStatus(),
        repository.canManageAttendance(),
      ]);

      final workspace = values[3] as Map<String, dynamic>;
      final selection = workspace['selection'] is Map
          ? Map<String, dynamic>.from(workspace['selection'] as Map)
          : const <String, dynamic>{};
      final schedule = workspace['gps_schedule'] is Map
          ? Map<String, dynamic>.from(workspace['gps_schedule'] as Map)
          : const <String, dynamic>{};
      final status = values[4] as HomeAttendanceStatus;

      final scheduleDays = schedule['weekdays'] is List
          ? (schedule['weekdays'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false)
          : const <int>[1, 2, 3, 4, 5];

      var selectedMode = selection['mode']?.toString() ??
          (schedule['enabled'] == true ? 'gps_auto' : 'none');
      if (selectedMode == 'location') selectedMode = 'gps_auto';

      final sites = values[1] as List<Map<String, dynamic>>;
      final destination = resolveAttendanceClockInDestination(
        selection: selection, gpsSchedule: schedule,
        selectedRouteId: status.selectedRouteId,
      );

      final pendingCapture = await repository.loadPendingCaptureDraft();
      final journeyShifts = <AttendanceShiftContext>[];
      List<String> pendingJourneySourceIds = const [];
      final journeys = _journeyRepository;
      if (journeys != null) {
        // Staged optional feature must never block existing attendance loading.
        try { pendingJourneySourceIds = (await journeys.allPending()).map((draft) => draft.sourceId).toList(); } catch (_) { /* Preserve the stored record. */ }
        for (final shift in status.openShifts.where((row) => row.routeId != null && row.verificationMode == 'location_photo')) {
          if (await journeys.enabled(shift.id)) journeyShifts.add(shift);
        }
      }
      if (!mounted) return;
      setState(() {
        _workers = values[0] as List<Map<String, dynamic>>;
        _sites = sites
            .where((row) => row['status']?.toString() != 'completed' || status.openShifts.any((shift) => shift.siteId == row['id']?.toString()))
            .toList(growable: false);
        _recent = values[2] as List<Map<String, dynamic>>;
        _workerId =
            _workers.isEmpty ? null : _workers.first['id']?.toString();
        _siteId = destination.siteId;
        _mode = selectedMode;
        _gpsWeekdays =
            scheduleDays.isEmpty ? const [1, 2, 3, 4, 5] : scheduleDays;
        _gpsTime = gpsTimeFromDatabase(schedule['local_time']);
        _vehicleName = status.selectedVehicleName;
        _vehicleId = status.selectedVehicleId;
        _routeId = destination.routeId;
        _routeName = status.selectedRouteName;
        _canManageAttendance = values[5] == true;
        _openShifts = status.openShifts;
        _journeyShifts = journeyShifts;
        _pendingJourneySourceIds = pendingJourneySourceIds;
        _shift = _eventType == 'clock_out' && _openShifts.length == 1 ? _openShifts.single : null;
        if (_shift != null) _selectShift(_shift!);
        _pendingCaptureDraft = pendingCapture;
        if (pendingCapture != null) {
          _shift = null;
          for (final shift in _openShifts) {
            if (shift.id == pendingCapture.payload['source_clock_in_id']) { _shift = shift; }
          }
          _eventType = pendingCapture.payload['event_type'] as String;
          _mode = 'location_photo';
          _workerId = pendingCapture.payload['worker_id'] as String;
          _siteId = pendingCapture.payload['site_id'] as String?;
          _routeId = pendingCapture.payload['route_assignment_id'] as String?;
          _vehicleId = pendingCapture.payload['vehicle_id'] as String?;
          _noteController.text = pendingCapture.payload['note'] as String? ?? '';
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _selectShift(AttendanceShiftContext shift) {
    _shift = shift;
    _siteId = shift.siteId;
    _routeId = shift.routeId;
    _routeName = shift.routeName;
    _vehicleName = shift.vehicleName;
    _vehicleId = shift.vehicleId;
    if (_mode == 'none') {
      _mode = shift.verificationMode == 'gps_auto' ? 'gps_auto' : 'manual';
    }
  }

  String _shiftLabel(AttendanceShiftContext shift) {
    final time = shift.clockIn;
    return '${shift.workDate.month}/${shift.workDate.day} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} '
        '${shift.siteName ?? shift.routeName ?? '勤務'}';
  }

  Future<void> _openPastBulkAttendance() async {
    final repository = _bulkAttendanceRepository;
    if (repository == null) return;
    final count = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => BulkAttendancePage(repository: repository),
      ),
    );
    if (count == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count件の過去出勤をまとめて登録しました')),
    );
    await _load();
  }

  Future<void> _changeMode(String? value) async {
    if (value == null) return;
    if (value != 'gps_auto') {
      setState(() => _mode = value);
      return;
    }

    final schedule = await showGpsAutoScheduleDialog(
      context,
      initialWeekdays: _gpsWeekdays,
      initialTime: _gpsTime,
    );
    if (schedule == null || !mounted) return;

    setState(() {
      _mode = 'gps_auto';
      _gpsWeekdays = schedule.weekdays;
      _gpsTime = schedule.time;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isClockOut = _eventType == 'clock_out';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: Text(
          isClockOut ? '退勤' : '出勤',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _editingLocked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (_pendingCaptureDraft != null)
                    Card(child: Padding(padding: const EdgeInsets.all(12),
                      child: Text(SkoLanguageController.tr('撮影記録の登録結果が未確認です。同じ記録で再確認してください。対象・写真は変更できません。')))),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  for (final pendingJourneySourceId in _pendingJourneySourceIds)
                    OutlinedButton.icon(onPressed: _saving ? null : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteJourneyCapturePage(sourceId: pendingJourneySourceId)));
                      if (mounted) await _load();
                    }, icon: const Icon(Icons.camera_alt_outlined), label: Text(SkoLanguageController.tr('保留中の途中現場記録を再確認'))),
                  for (final journey in _journeyShifts)
                    OutlinedButton.icon(onPressed: _saving || _pendingCaptureDraft != null ? null : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteJourneyCapturePage(sourceId: journey.id)));
                      if (mounted) await _load();
                    }, icon: const Icon(Icons.add_a_photo_outlined), label: Text('${SkoLanguageController.tr('途中現場のGPS＋写真')}: ${_shiftLabel(journey)}')),
                  if (isClockOut && _openShifts.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('shift:${_shift?.id}:${_openShifts.length}'),
                      initialValue: _shift?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '退勤する勤務',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final shift in _openShifts)
                          DropdownMenuItem(value: shift.id, child: Text(_shiftLabel(shift), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _editingLocked ? null : (value) {
                        if (value == null) return;
                        setState(() => _selectShift(_openShifts.firstWhere((shift) => shift.id == value)));
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    key: ValueKey('method:$_mode'),
                    initialValue: _mode,
                    decoration: const InputDecoration(
                      labelText: '出勤方法',
                      prefixIcon: Icon(Icons.tune_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('未選択'),
                      ),
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text('手動'),
                      ),
                      DropdownMenuItem(
                        value: 'gps_auto',
                        child: Text('GPS自動出勤'),
                      ),
                      DropdownMenuItem(
                        value: 'location_photo',
                        child: Text('位置情報＋写真（確定時のみ）'),
                      ),
                    ],
                    onChanged: _editingLocked ? null : _changeMode,
                  ),
                  if (_mode == 'gps_auto') ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('選択中の曜日とGPS取得時間'),
                        subtitle: Text(
                          GpsAutoScheduleDraft(
                            weekdays: _gpsWeekdays,
                            time: _gpsTime,
                          ).label,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _editingLocked
                            ? null
                            : () async {
                                final schedule =
                                    await showGpsAutoScheduleDialog(
                                  context,
                                  initialWeekdays: _gpsWeekdays,
                                  initialTime: _gpsTime,
                                );
                                if (schedule != null && mounted) {
                                  setState(() {
                                    _gpsWeekdays = schedule.weekdays;
                                    _gpsTime = schedule.time;
                                  });
                                }
                              },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AttendanceDestinationSiteField(
                    siteId: _siteId,
                    routeId: _routeId,
                    sites: _sites,
                    locked: _editingLocked || _shift != null,
                    onChanged: (value) => setState(() => _siteId = value),
                  ),
                  if (_selectedSite != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _siteLocationText(_selectedSite!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_canManageAttendance)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              _editingLocked ? null : _setSelectedSiteLocation,
                          icon: const Icon(Icons.my_location),
                          label: const Text('この現場の基準位置を現在地で登録'),
                        ),
                      ),
                  ],
                  if ((_vehicleName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ReadOnlySelectionCard(
                      icon: Icons.directions_car_outlined,
                      label: '車両',
                      value: _vehicleName!,
                    ),
                  ],
                  if ((_routeName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ReadOnlySelectionCard(
                      icon: Icons.route_outlined,
                      label: 'ルート',
                      value: _routeName!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    enabled: !_editingLocked,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving || (_pendingCaptureDraft == null && _savedCaptureVerification == null && (
                            _workerId == null ||
                            (_siteId == null && _routeId == null) ||
                            (isClockOut && _openShifts.length > 1 && _shift == null)))
                        ? null
                        : _confirm,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isClockOut ? Icons.logout : Icons.login),
                    label: Text(
                      _saving
                          ? '確認中…'
                          : _savedCaptureVerification != null
                              ? SkoLanguageController.tr('登録済みの日報を開く')
                              : _pendingCaptureDraft != null
                              ? SkoLanguageController.tr('同じ撮影記録で再確認')
                              : isClockOut
                              ? '退勤を確定'
                              : '出勤を確定',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  if (!isClockOut && _canManageAttendance) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _editingLocked ? null : _openPastBulkAttendance,
                      icon: const Icon(Icons.playlist_add_check_circle_outlined),
                      label: const Text('過去の出勤をまとめて登録する'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '最近の確認',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_recent.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('確認履歴はまだありません。'),
                      ),
                    )
                  else
                    for (final item in _recent)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            item['event_type'] == 'clock_in'
                                ? Icons.login
                                : Icons.logout,
                          ),
                          title: Text(
                            '${_workerName(item)} / ${_siteName(item)}',
                          ),
                          subtitle: Text(
                            '${_eventLabel(item['event_type'])} ・ '
                            '${_modeLabel(item['verification_mode'])}\n'
                            '${_statusLabel(item)}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                ],
              ),
      ),
    );
  }

  Map<String, dynamic>? get _selectedSite {
    final id = _siteId;
    if (id == null) return null;
    for (final site in _sites) {
      if (site['id']?.toString() == id) return site;
    }
    return null;
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('端末の位置情報サービスをONにしてください。');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('位置情報の許可が必要です。');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        '位置情報が拒否されています。iPhone設定からSKOの位置情報を許可してください。',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<void> _setSelectedSiteLocation() async {
    final repository = _repository;
    final siteId = _siteId;
    if (repository == null || siteId == null) return;

    setState(() => _saving = true);
    try {
      final position = await _currentPosition();
      await repository.updateSiteLocation(
        siteId: siteId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場の基準位置を登録しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現場位置を登録できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    final repository = _repository;
    final workerId = _workerId;
    final siteId = _siteId;
    if (_saving || repository == null ||
        (_pendingCaptureDraft == null && _savedCaptureVerification == null &&
          ((_openShifts.length > 1 && _eventType == 'clock_out' && _shift == null) ||
           workerId == null || (siteId == null && _routeId == null)))) {
      return;
    }

    if (_mode == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出勤方法を選択してください')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final completed = _savedCaptureVerification;
      if (completed != null) {
        await _finishSavedVerification(completed);
        return;
      }
      final pending = _pendingCaptureDraft;
      if (pending != null) {
        final saved = await repository.submitCaptureDraft(pending);
        if (mounted) { setState(() {
          _pendingCaptureDraft = null;
          _savedCaptureVerification = saved;
        }); }
        await _finishSavedVerification(saved);
        return;
      }
      if (workerId == null) { throw StateError('社員情報を確認してください'); }
      if (_mode == 'gps_auto') {
        final allowed = await ensureGpsAutoLocationPermission(context);
        if (!allowed || !mounted) return;
      }
      if (_eventType == 'clock_in') {
        await repository.saveAttendanceSelection(
        mode: _mode,
        siteId: siteId,
        weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
        localTime: _mode == 'gps_auto'
            ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
            : null,
      );
        await GpsAutoAttendanceService.instance.refresh();
      }

      if (_mode == 'gps_auto' && _eventType == 'clock_in') {
        final position = await _currentPosition();
        final result = await repository.attemptGpsAutoAttendance(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyM: position.accuracy,
        );
        if (!mounted) return;
        final status = result['status']?.toString() ?? '';
        final message = switch (status) {
          'clocked_in' => 'GPS自動出勤で出勤を記録しました',
          'outside_site' => '現場にいないようなのでGPS自動出勤は出勤を登録しませんでした',
          'site_location_missing' =>
            '現場の基準位置が未登録のためGPS自動出勤を登録しませんでした',
          'route_location_missing' =>
            'ルート内の駐車場・経由地にGPS基準位置がないため自動出勤を登録しませんでした',
          'already_recorded' => '本日の出勤はすでに登録されています',
          _ => 'GPS自動出勤の曜日・取得時間を保存しました',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        Navigator.of(context).pop(true);
        return;
      }

      double? latitude;
      double? longitude;
      double? accuracy;
      double? distance;
      var proximityStatus = 'not_checked';
      Uint8List? photoBytes;
      String? photoFilename;

      GpsPhotoCaptureResult? capture;
      if (_mode == 'location_photo' && await repository.captureEnabled()) {
        final captureContext = CaptureShiftContext(
          companyId: await repository.captureCompanyId(),
          workDate: (_shift?.workDate ?? DateTime.now()).toIso8601String().substring(0, 10),
          requestedMethod: _mode, sourceClockInId: _shift?.id,
          siteId: siteId, routeId: _shift?.routeId ?? _routeId,
          vehicleId: _shift?.vehicleId ?? _vehicleId);
        capture = await GpsPhotoCaptureController(
          camera: () async {
            final image = await _picker.pickImage(source: ImageSource.camera,
              imageQuality: 85, maxWidth: 2200);
            if (image == null) { return null; }
            final observedAt = DateTime.now();
            return CapturedPhoto(bytes: await image.readAsBytes(), observedAt: observedAt,
              capturedAt: await _captureMetadata.readPhotoCapturedAt(image.path));
          },
          sampleGps: () async {
            final position = await _currentPosition();
            return CapturedGpsSample(latitude: position.latitude,
              longitude: position.longitude, sampledAt: position.timestamp,
              accuracyM: position.accuracy,
              address: await _captureMetadata.reverseGeocodeCapturedLocation(
                latitude: position.latitude, longitude: position.longitude));
          },
          upload: (photo, context) => repository.uploadCapturedPhoto(photo, context, workerId),
          prompt: _promptCaptureFailure, now: DateTime.now,
        ).capture(captureContext);
        latitude = capture.gps?.latitude;
        longitude = capture.gps?.longitude;
        accuracy = capture.gps?.accuracyM;
      }

      if (capture == null && (_mode == 'location_photo' || _mode == 'gps_auto')) {
        final position = await _currentPosition();
        latitude = position.latitude;
        longitude = position.longitude;
        accuracy = position.accuracy;

        final site = _selectedSite;
        final siteLatitude = _asDouble(site?['latitude']);
        final siteLongitude = _asDouble(site?['longitude']);
        if (siteId == null) {
          proximityStatus = 'not_checked';
        } else if (siteLatitude == null || siteLongitude == null) {
          proximityStatus = 'site_location_missing';
        } else {
          distance = Geolocator.distanceBetween(
            latitude,
            longitude,
            siteLatitude,
            siteLongitude,
          );
          proximityStatus =
              distance <= 300 ? 'near_site' : 'outside_radius';
        }
      }

      if (capture != null && latitude != null && longitude != null) {
        final siteLatitude = _asDouble(_selectedSite?['latitude']);
        final siteLongitude = _asDouble(_selectedSite?['longitude']);
        if (siteId != null && siteLatitude != null && siteLongitude != null) {
          distance = Geolocator.distanceBetween(latitude, longitude, siteLatitude, siteLongitude);
          proximityStatus = distance <= 300 ? 'near_site' : 'outside_radius';
        } else if (siteId != null) {
          proximityStatus = 'site_location_missing';
        }
      }

      if (_mode == 'location_photo' && capture == null) {
        final photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2200,
        );
        if (photo == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('写真撮影をキャンセルしたため、確認は登録していません。'),
            ),
          );
          return;
        }
        photoBytes = await photo.readAsBytes();
        photoFilename = photo.name;
      }

      final saved = await repository.createVerification(
        workerId: workerId,
        siteId: siteId,
        eventType: _eventType,
        verificationMode: _mode,
        latitude: latitude,
        longitude: longitude,
        accuracyM: accuracy,
        distanceToSiteM: distance,
        proximityStatus: proximityStatus,
        photoBytes: photoBytes,
        photoFilename: photoFilename,
        note: _noteController.text,
        shift: _shift,
        capture: capture,
        onCaptureDraftPrepared: (draft) {
          if (mounted) { setState(() => _pendingCaptureDraft = draft); }
        },
      );

      if (mounted) { setState(() {
        _pendingCaptureDraft = null;
        if (capture != null) { _savedCaptureVerification = saved; }
      }); }
      await _finishSavedVerification(saved);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('確認を登録できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishSavedVerification(Map<String, dynamic> saved) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _eventType == 'clock_in' ? '出勤を確認しました' : '退勤を確認しました',
          ),
        ),
      );

      if (_eventType == 'clock_out') {
        final sourceId = saved['source_clock_in_id']?.toString() ?? _shift?.id;
        final date = DateTime.tryParse(saved['work_date']?.toString() ?? '') ?? _shift?.workDate;
        final siteId = saved['site_id']?.toString() ?? _shift?.siteId ?? _siteId;
        final routeId = saved['route_assignment_id']?.toString() ?? _shift?.routeId ?? _routeId;
        if (sourceId != null && date != null && siteId != null && routeId == null) {
          await showGroupCheckoutAfterPersonalSave(context, anchorId: sourceId, workDate: date);
          if (!mounted) return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DailyReportPage(
            initialDate: DateTime.tryParse(saved['work_date']?.toString() ?? '') ?? _shift?.workDate,
            initialSiteId: saved['site_id']?.toString() ?? _shift?.siteId ?? _siteId,
            initialRouteAssignmentId: saved['route_assignment_id']?.toString() ?? _shift?.routeId ?? _routeId,
            vehicleClockInId: saved['source_clock_in_id']?.toString() ?? _shift?.id,
            groupClockInAnchorId: saved['source_clock_in_id']?.toString() ?? _shift?.id,
          )),
        );
      } else {
        Navigator.of(context).pop(true);
      }
  }

  Future<CaptureDecision> _promptCaptureFailure(CaptureFailure failure) async {
    if (!mounted) { return CaptureDecision.confirm; }
    final message = switch (failure) {
      CaptureFailure.camera => '写真が未登録です。撮り直すか、未登録の状態を残して確認してください。',
      CaptureFailure.gps => '撮影時のGPSを取得できませんでした。撮り直すか、取得失敗を残して確認してください。',
      CaptureFailure.upload => '写真の送信に失敗しました。撮り直すか、送信失敗を残して確認してください。',
    };
    return await showDialog<CaptureDecision>(context: context, barrierDismissible: false,
      builder: (context) => AlertDialog(title: Text(SkoLanguageController.tr('撮影情報の確認')),
        content: Text(SkoLanguageController.tr(message)), actions: [
          TextButton(onPressed: () => Navigator.pop(context, CaptureDecision.retake),
            child: Text(SkoLanguageController.tr('撮り直す'))),
          FilledButton(onPressed: () => Navigator.pop(context, CaptureDecision.confirm),
            child: Text(SkoLanguageController.tr('確認'))),
        ])) ?? CaptureDecision.confirm;
  }

  String _modeLabel(Object? mode) => switch (mode?.toString()) {
        'none' => '未選択',
        'gps_auto' || 'location' => 'GPS自動出勤',
        'location_photo' => '位置情報＋写真',
        _ => '手動',
      };

  String _eventLabel(Object? eventType) =>
      eventType == 'clock_out' ? '退勤' : '出勤';

  String _workerName(Map<String, dynamic> item) {
    final worker = item['workers'];
    return worker is Map ? worker['name']?.toString() ?? '' : '';
  }

  String _siteName(Map<String, dynamic> item) {
    final site = item['sites'];
    final siteName = site is Map ? site['name']?.toString().trim() ?? '' : '';
    if (siteName.isNotEmpty) return siteName;
    final route = item['route_assignments'];
    final routeName =
        route is Map ? route['route_name']?.toString().trim() ?? '' : '';
    return routeName.isNotEmpty ? routeName : '勤務先未登録';
  }

  String _statusLabel(Map<String, dynamic> item) {
    switch (item['proximity_status']) {
      case 'near_site':
        final distance = _asDouble(item['distance_to_site_m']);
        return distance == null
            ? '現場付近で確認'
            : '現場付近で確認（約${distance.round()}m）';
      case 'outside_radius':
        final distance = _asDouble(item['distance_to_site_m']);
        return distance == null
            ? '基準範囲外'
            : '基準範囲外（約${distance.round()}m）';
      case 'site_location_missing':
        return '位置取得済み・現場基準位置未登録';
      default:
        return '本人操作で確認';
    }
  }

  String _siteLocationText(Map<String, dynamic> site) {
    final lat = _asDouble(site['latitude']);
    final lon = _asDouble(site['longitude']);
    if (lat == null || lon == null) return '基準位置: 未登録';
    return '基準位置: 登録済み / GPS判定半径 300m';
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _ReadOnlySelectionCard extends StatelessWidget {
  const _ReadOnlySelectionCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
