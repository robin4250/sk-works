import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../daily_reports/daily_report_page.dart';
import '../notifications/notification_bell.dart';
import 'attendance_verification_repository.dart';
import 'gps_auto_attendance_service.dart';
import 'gps_auto_schedule_dialog.dart';

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
  final _picker = ImagePicker();
  final _noteController = TextEditingController();

  List<Map<String, dynamic>> _workers = const [];
  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _recent = const [];

  String _mode = 'manual';
  String? _workerId;
  String? _siteId;
  late String _eventType;
  List<int> _gpsWeekdays = const [1, 2, 3, 4, 5];
  TimeOfDay _gpsTime = const TimeOfDay(hour: 8, minute: 0);

  String? _vehicleName;
  String? _routeId;
  String? _routeName;

  bool _loading = true;
  bool _saving = false;
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
          (schedule['enabled'] == true ? 'gps_auto' : 'manual');
      if (selectedMode == 'location') selectedMode = 'gps_auto';

      final sites = values[1] as List<Map<String, dynamic>>;
      final selectedSiteId = selection['site_id']?.toString() ??
          schedule['site_id']?.toString() ??
          (sites.isEmpty ? null : sites.first['id']?.toString());

      if (!mounted) return;
      setState(() {
        _workers = values[0] as List<Map<String, dynamic>>;
        _sites = sites
            .where((row) => row['status']?.toString() != 'completed')
            .toList(growable: false);
        _recent = values[2] as List<Map<String, dynamic>>;
        _workerId =
            _workers.isEmpty ? null : _workers.first['id']?.toString();
        _siteId = selectedSiteId;
        _mode = selectedMode;
        _gpsWeekdays =
            scheduleDays.isEmpty ? const [1, 2, 3, 4, 5] : scheduleDays;
        _gpsTime = gpsTimeFromDatabase(schedule['local_time']);
        _vehicleName = status.selectedVehicleName;
        _routeId = status.selectedRouteId;
        _routeName = status.selectedRouteName;
        _canManageAttendance = values[5] == true;
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
        title: Text(
          isClockOut ? '退勤' : '出勤',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            tooltip: '再読み込み',
            onPressed: _saving ? null : _load,
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
                  DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(
                      labelText: '出勤方法',
                      prefixIcon: Icon(Icons.tune_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
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
                    onChanged: _saving ? null : _changeMode,
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
                        onTap: _saving
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
                  DropdownButtonFormField<String?>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(
                      labelText: '現場',
                      prefixIcon: Icon(Icons.business_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未登録（ルートで出勤）'),
                      ),
                      for (final site in _sites)
                        DropdownMenuItem<String?>(
                          value: site['id']?.toString(),
                          child: Text(site['name']?.toString() ?? '現場'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _siteId = value),
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
                              _saving ? null : _setSelectedSiteLocation,
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
                    enabled: !_saving,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ||
                            _workerId == null ||
                            (_siteId == null && _routeId == null)
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
                          : isClockOut
                              ? '退勤を確定'
                              : '出勤を確定',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
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
    if (repository == null ||
        workerId == null ||
        (siteId == null && _routeId == null)) {
      return;
    }

    if (_mode == 'gps_auto' && siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS自動出勤は現場の選択が必要です')),
      );
      return;
    }

    if (_mode == 'gps_auto') {
      final allowed = await ensureGpsAutoLocationPermission(context);
      if (!allowed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await repository.saveAttendanceSelection(
        mode: _mode,
        siteId: siteId,
        weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
        localTime: _mode == 'gps_auto'
            ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
            : null,
      );
      await GpsAutoAttendanceService.instance.refresh();

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

      if (_mode == 'location_photo' || _mode == 'gps_auto') {
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

      if (_mode == 'location_photo') {
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

      await repository.createVerification(
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
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _eventType == 'clock_in' ? '出勤を確認しました' : '退勤を確認しました',
          ),
        ),
      );

      if (_eventType == 'clock_out') {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DailyReportPage()),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('確認を登録できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _modeLabel(Object? mode) => switch (mode?.toString()) {
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
