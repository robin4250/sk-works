import 'package:flutter/material.dart';

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
  final _repository = AttendanceVerificationRepository.maybeCreate();

  List<Map<String, dynamic>> _sites = const [];
  String _mode = 'manual';
  String? _siteId;
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
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = '出勤設定を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        repository.loadSites(),
        repository.loadAttendanceSelectionWorkspace(),
      ]);
      final sites = values[0] as List<Map<String, dynamic>>;
      final workspace = values[1] as Map<String, dynamic>;
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

      if (!mounted) return;
      setState(() {
        _sites = sites
            .where((row) => row['status']?.toString() != 'completed')
            .toList(growable: false);
        _mode = selection['mode']?.toString() ??
            (schedule['enabled'] == true ? 'gps_auto' : 'manual');
        if (_mode == 'location') _mode = 'gps_auto';
        _siteId = selection['site_id']?.toString() ??
            schedule['site_id']?.toString();
        _gpsWeekdays = scheduleDays.isEmpty
            ? const [1, 2, 3, 4, 5]
            : scheduleDays;
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
    final repository = _repository;
    final siteId = _siteId;
    if (repository == null || siteId == null || _saving) return;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '出勤方法と現場の選択',
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
                      DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(
                          labelText: '出勤方法の選択',
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
                        onChanged: _saving ? null : _chooseMode,
                      ),
                      if (_mode == 'gps_auto') ...[
                        const SizedBox(height: 10),
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
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        initialValue: _siteId,
                        decoration: const InputDecoration(
                          labelText: '現場の選択',
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
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(_saving ? '保存中…' : '保存してTOPへ戻る'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
