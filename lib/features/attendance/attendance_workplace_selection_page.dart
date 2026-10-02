import 'package:flutter/material.dart';

import '../operations/vehicle_route_repository.dart';
import 'attendance_verification_repository.dart';
import 'gps_auto_schedule_dialog.dart';

class AttendanceWorkplaceSelectionPage extends StatefulWidget {
  const AttendanceWorkplaceSelectionPage({super.key});

  @override
  State<AttendanceWorkplaceSelectionPage> createState() =>
      _AttendanceWorkplaceSelectionPageState();
}

class _AttendanceWorkplaceSelectionPageState
    extends State<AttendanceWorkplaceSelectionPage> {
  final _attendanceRepository = AttendanceVerificationRepository.maybeCreate();
  final _routeRepository = VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _routes = const [];
  String _kind = 'site';
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
    final attendance = _attendanceRepository;
    final routes = _routeRepository;
    if (attendance == null || routes == null) {
      setState(() {
        _loading = false;
        _error = '勤務先選択を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        attendance.loadSites(),
        attendance.loadAttendanceSelectionWorkspace(),
        routes.routes(activeOnly: true),
        routes.loadTodaySelection(),
      ]);
      final workspace = values[1] as Map<String, dynamic>;
      final selection = workspace['selection'] is Map
          ? Map<String, dynamic>.from(workspace['selection'] as Map)
          : const <String, dynamic>{};
      final schedule = workspace['gps_schedule'] is Map
          ? Map<String, dynamic>.from(workspace['gps_schedule'] as Map)
          : const <String, dynamic>{};
      final routeSelection = values[3] as Map<String, dynamic>;
      final routeId = selection['route_assignment_id']?.toString() ??
          routeSelection['route_assignment_id']?.toString();

      if (!mounted) return;
      setState(() {
        _sites = (values[0] as List<Map<String, dynamic>>)
            .where((row) => row['status']?.toString() != 'completed')
            .toList(growable: false);
        _routes = values[2] as List<Map<String, dynamic>>;
        _siteId = selection['site_id']?.toString();
        _routeId = routeId;
        _kind = routeId?.isNotEmpty == true ? 'route' : 'site';
        _mode = selection['mode']?.toString() ??
            (schedule['enabled'] == true ? 'gps_auto' : 'manual');
        final rawDays = schedule['weekdays'];
        _gpsWeekdays = rawDays is List
            ? rawDays.whereType<num>().map((e) => e.toInt()).toList()
            : const [1, 2, 3, 4, 5];
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

  Future<void> _save() async {
    final attendance = _attendanceRepository;
    final routes = _routeRepository;
    if (attendance == null || routes == null || _saving) return;

    setState(() => _saving = true);
    try {
      if (_kind == 'route') {
        await routes.saveTodayRouteSelection(_routeId);
        await attendance.saveAttendanceSelection(
          mode: _mode,
          siteId: null,
          weekdays: _mode == 'gps_auto' ? _gpsWeekdays : null,
          localTime: _mode == 'gps_auto'
              ? '${_gpsTime.hour.toString().padLeft(2, '0')}:${_gpsTime.minute.toString().padLeft(2, '0')}:00'
              : null,
        );
      } else {
        await attendance.saveAttendanceSelection(
          mode: _mode,
          siteId: _siteId,
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
                      const Text(
                        '今日の勤務先を「1つの現場」か「複数現場を回るルート」のどちらか一方で選びます。',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'site',
                            icon: Icon(Icons.business_outlined),
                            label: Text('1つの現場'),
                          ),
                          ButtonSegment(
                            value: 'route',
                            icon: Icon(Icons.route_outlined),
                            label: Text('複数現場'),
                          ),
                        ],
                        selected: {_kind},
                        onSelectionChanged: _saving
                            ? null
                            : (values) => setState(() {
                                  _kind = values.first;
                                  if (_kind == 'site') {
                                    _routeId = null;
                                  } else {
                                    _siteId = null;
                                  }
                                }),
                      ),
                      const SizedBox(height: 16),
                      if (_kind == 'site')
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
                              : (value) => setState(() => _siteId = value),
                        )
                      else
                        DropdownButtonFormField<String?>(
                          initialValue: _routeId,
                          decoration: const InputDecoration(
                            labelText: 'ルート',
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
                              : (value) => setState(() => _routeId = value),
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
