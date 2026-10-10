import 'package:flutter/material.dart';

import '../operations/vehicle_route_repository.dart';
import '../operations/route_stops_preview.dart';
import 'attendance_verification_repository.dart';
import 'gps_auto_schedule_dialog.dart';

class WorkDestinationSelectionPage extends StatefulWidget {
  const WorkDestinationSelectionPage({super.key});

  @override
  State<WorkDestinationSelectionPage> createState() =>
      _WorkDestinationSelectionPageState();
}

class _WorkDestinationSelectionPageState
    extends State<WorkDestinationSelectionPage> {
  final _attendanceRepository = AttendanceVerificationRepository.maybeCreate();
  final _vehicleRouteRepository = VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _routes = const [];
  String? _siteId;
  String? _routeId;
  String _mode = 'manual';
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
        _error = '勤務先選択を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        attendanceRepository.loadSites(),
        attendanceRepository.loadAttendanceSelectionWorkspace(),
        vehicleRouteRepository.routes(activeOnly: true),
        vehicleRouteRepository.loadTodaySelection(),
      ]);

      final sites = values[0] as List<Map<String, dynamic>>;
      final workspace = values[1] as Map<String, dynamic>;
      final routes = values[2] as List<Map<String, dynamic>>;
      final routeSelection = values[3] as Map<String, dynamic>;
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
          (schedule['enabled'] == true ? 'gps_auto' : 'manual');
      if (mode == 'location') mode = 'gps_auto';

      final selectedSiteId = selection['site_id']?.toString();
      final selectedRouteId = selection['route_assignment_id']?.toString() ??
          routeSelection['route_assignment_id']?.toString();

      if (!mounted) return;
      setState(() {
        _sites = sites
            .where((row) => row['status']?.toString() != 'completed')
            .toList(growable: false);
        _routes = routes;
        _siteId = selectedSiteId;
        _routeId = selectedSiteId != null ? null : selectedRouteId;
        _mode = mode;
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

  Future<void> _showExclusiveGuide({required bool fixedSite}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fixedSite ? '固定の1現場へ出勤' : '複数現場を回るルートへ出勤'),
        content: Text(
          fixedSite
              ? '勤務先は「固定の1つの現場」か「複数の現場を回るルート」のどちらか一方です。固定現場を選ぶと、今日のルート選択は解除されます。'
              : '勤務先は「固定の1つの現場」か「複数の現場を回るルート」のどちらか一方です。ルートを選ぶと、今日の固定現場選択は解除されます。車両は別の任意選択なので、徒歩や電車でもルート勤務できます。',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final attendanceRepository = _attendanceRepository;
    final vehicleRouteRepository = _vehicleRouteRepository;
    if (attendanceRepository == null ||
        vehicleRouteRepository == null ||
        _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      if (_siteId != null) {
        await attendanceRepository.saveAttendanceSelection(
          mode: _mode,
          siteId: _siteId,
          weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
          localTime: _mode == 'gps_auto'
              ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
              : null,
        );
        await vehicleRouteRepository.saveTodayRouteSelection(null);
      } else if (_routeId != null) {
        await vehicleRouteRepository.saveTodayRouteSelection(_routeId);
        await attendanceRepository.saveAttendanceSelection(
          mode: _mode,
          siteId: null,
          weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
          localTime: _mode == 'gps_auto'
              ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
              : null,
        );
      } else {
        await vehicleRouteRepository.saveTodayRouteSelection(null);
        await attendanceRepository.saveAttendanceSelection(
          mode: _mode,
          siteId: null,
          weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
          localTime: _mode == 'gps_auto'
              ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
              : null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('勤務先を保存できませんでした: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: const Text(
          '現場の選択',
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
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            '勤務先はどちらか一方です。\n'
                            '・固定の1現場へ出勤 → 現場を選択\n'
                            '・外回りで複数現場へ出勤 → ルートを選択\n'
                            '車両を使うかどうかは別画面で選択します。',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: _siteId,
                        decoration: const InputDecoration(
                          labelText: '固定の1現場',
                          prefixIcon: Icon(Icons.business_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('未登録'),
                          ),
                          for (final site in _sites)
                            DropdownMenuItem<String?>(
                              value: site['id']?.toString(),
                              child: Text(site['name']?.toString() ?? '現場'),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) async {
                                if (value != null &&
                                    value != _siteId &&
                                    _routeId != null) {
                                  await _showExclusiveGuide(fixedSite: true);
                                }
                                if (!mounted) return;
                                setState(() {
                                  _siteId = value;
                                  if (value != null) _routeId = null;
                                });
                              },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        initialValue: _routeId,
                        decoration: const InputDecoration(
                          labelText: '複数現場のルート',
                          prefixIcon: Icon(Icons.route_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('未登録'),
                          ),
                          for (final route in _routes)
                            DropdownMenuItem<String?>(
                              value: route['id']?.toString(),
                              child: Text(
                                route['route_name']?.toString() ?? 'ルート',
                              ),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) async {
                                if (value != null &&
                                    value != _routeId &&
                                    _siteId != null) {
                                  await _showExclusiveGuide(fixedSite: false);
                                }
                                if (!mounted) return;
                                setState(() {
                                  _routeId = value;
                                  if (value != null) _siteId = null;
                                });
                              },
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(_saving ? '保存中…' : '確定して保存'),
                      ),
                      if (_siteId == null)
                        RouteStopsPreview(
                          route: _routes.where((row) => row['id'] == _routeId).firstOrNull,
                        ),
                    ],
                  ),
      ),
    );
  }
}
