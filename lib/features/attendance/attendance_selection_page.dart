import 'package:flutter/material.dart';

import '../operations/vehicle_route_repository.dart';
import 'attendance_verification_repository.dart';
import 'gps_auto_attendance_service.dart';
import 'gps_auto_schedule_dialog.dart';

class AttendanceSelectionPage extends StatefulWidget {
  const AttendanceSelectionPage({super.key});

  @override
  State<AttendanceSelectionPage> createState() =>
      _AttendanceSelectionPageState();
}

class _AttendanceSelectionPageState extends State<AttendanceSelectionPage> {
  final _attendanceRepository = AttendanceVerificationRepository.maybeCreate();
  final _vehicleRouteRepository = VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _vehicles = const [];
  String _mode = 'none';
  String? _siteId;
  String? _routeId;
  String? _vehicleId;
  List<int> _gpsWeekdays = const [1, 2, 3, 4, 5];
  TimeOfDay _gpsTime = const TimeOfDay(hour: 8, minute: 0);
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attendanceRepository = _attendanceRepository;
    final vehicleRouteRepository = _vehicleRouteRepository;
    if (attendanceRepository == null || vehicleRouteRepository == null) {
      setState(() {
        _loading = false;
        _error = '出勤方法・車両選択を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        attendanceRepository.loadAttendanceSelectionWorkspace(),
        vehicleRouteRepository.vehicles(activeOnly: true),
        vehicleRouteRepository.loadTodaySelection(),
      ]);
      final workspace = values[0] as Map<String, dynamic>;
      final vehicles = values[1] as List<Map<String, dynamic>>;
      final vehicleSelection = values[2] as Map<String, dynamic>;
      final selection = workspace['selection'] is Map
          ? Map<String, dynamic>.from(workspace['selection'] as Map)
          : const <String, dynamic>{};
      final schedule = workspace['gps_schedule'] is Map
          ? Map<String, dynamic>.from(workspace['gps_schedule'] as Map)
          : const <String, dynamic>{};

      final scheduleDays = schedule['weekdays'] is List
          ? (schedule['weekdays'] as List)
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false)
          : const <int>[1, 2, 3, 4, 5];

      var mode = selection['mode']?.toString() ??
          (schedule['enabled'] == true ? 'gps_auto' : 'none');
      if (mode == 'location') mode = 'gps_auto';

      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _mode = mode;
        _siteId = selection['site_id']?.toString();
        _routeId = selection['route_assignment_id']?.toString() ??
            vehicleSelection['route_assignment_id']?.toString();
        _vehicleId = vehicleSelection['vehicle_id']?.toString();
        _gpsWeekdays =
            scheduleDays.isEmpty ? const [1, 2, 3, 4, 5] : scheduleDays;
        _gpsTime = gpsTimeFromDatabase(schedule['local_time']);
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

  Future<void> _chooseMode(String? value) async {
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

  Future<void> _save() async {
    final attendanceRepository = _attendanceRepository;
    final vehicleRouteRepository = _vehicleRouteRepository;
    if (attendanceRepository == null ||
        vehicleRouteRepository == null ||
        _saving) {
      return;
    }

    if (_mode == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出勤方法を選択してください')),
      );
      return;
    }

    if (_mode == 'gps_auto' && _siteId == null && _routeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS自動出勤は、固定現場またはルートを先に選択してください'),
        ),
      );
      return;
    }

    if (_mode == 'gps_auto') {
      final allowed = await ensureGpsAutoLocationPermission(context);
      if (!allowed || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await attendanceRepository.saveAttendanceSelection(
        mode: _mode,
        siteId: _siteId,
        weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
        localTime: _mode == 'gps_auto'
            ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
            : null,
      );
      await vehicleRouteRepository.saveTodayVehicleSelection(_vehicleId);
      await GpsAutoAttendanceService.instance.refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _destinationLabel {
    if (_siteId != null) return '固定現場を選択中';
    if (_routeId != null) return '複数現場のルートを選択中';
    return '勤務先は未登録';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: const Text(
          '出勤方法と車両を選択',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: const Text(
                            '勤務先',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Text(_destinationLabel),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
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
                        onChanged: _saving ? null : _chooseMode,
                      ),
                      if (_mode == 'gps_auto') ...[
                        const SizedBox(height: 10),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.schedule_outlined),
                            title: const Text('曜日とGPS取得時間'),
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
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        initialValue: _vehicleId,
                        decoration: const InputDecoration(
                          labelText: '車両（任意）',
                          prefixIcon: Icon(Icons.directions_car_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('車両を使わない'),
                          ),
                          for (final vehicle in _vehicles)
                            DropdownMenuItem<String?>(
                              value: vehicle['id']?.toString(),
                              child: Text(
                                vehicle['display_name']?.toString() ?? '車両',
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _vehicleId = value),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '車両は勤務先とは別の任意登録です。固定現場でもルートでも、使う場合だけ選択してください。',
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(_saving ? '保存中…' : '確定して保存'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
