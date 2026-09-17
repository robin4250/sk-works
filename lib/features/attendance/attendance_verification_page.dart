import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'attendance_verification_repository.dart';

class AttendanceVerificationPage extends StatefulWidget {
  const AttendanceVerificationPage({super.key});

  @override
  State<AttendanceVerificationPage> createState() => _AttendanceVerificationPageState();
}

class _AttendanceVerificationPageState extends State<AttendanceVerificationPage> {
  final _repository = AttendanceVerificationRepository.maybeCreate();
  final _picker = ImagePicker();
  final _noteController = TextEditingController();

  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _recent = [];
  String _mode = 'manual';
  int _radiusM = 300;
  String? _workerId;
  String? _siteId;
  String _eventType = 'clock_in';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final settings = await repository.loadSettings();
      final workers = await repository.loadWorkers();
      final sites = await repository.loadSites();
      final recent = await repository.loadRecent();
      if (!mounted) return;
      setState(() {
        _mode = settings['mode']?.toString() ?? 'manual';
        _radiusM = (settings['proximity_radius_m'] as num?)?.toInt() ?? 300;
        _workers = workers;
        _sites = sites;
        _recent = recent;
        _workerId ??= workers.isEmpty ? null : workers.first['id'] as String;
        _siteId ??= sites.isEmpty ? null : sites.first['id'] as String;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('出勤・退勤確認'),
        actions: [
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
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('確認方法', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _mode,
                            decoration: const InputDecoration(prefixIcon: Icon(Icons.verified_user_outlined)),
                            items: const [
                              DropdownMenuItem(value: 'manual', child: Text('手動のみ')),
                              DropdownMenuItem(value: 'location', child: Text('位置情報')),
                              DropdownMenuItem(value: 'location_photo', child: Text('位置情報＋写真')),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) async {
                                    if (value == null) return;
                                    setState(() => _mode = value);
                                    await _saveMode();
                                  },
                          ),
                          const SizedBox(height: 10),
                          Text(_modeDescription(_mode)),
                          const SizedBox(height: 8),
                          const Text(
                            '位置情報は出勤・退勤ボタンを押した時だけ取得します。常時GPS追跡はしません。',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _workerId,
                            decoration: const InputDecoration(labelText: '作業員', prefixIcon: Icon(Icons.person_outline)),
                            items: _workers
                                .map((worker) => DropdownMenuItem<String>(
                                      value: worker['id'] as String,
                                      child: Text(worker['name'].toString()),
                                    ))
                                .toList(),
                            onChanged: _saving ? null : (value) => setState(() => _workerId = value),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _siteId,
                            decoration: const InputDecoration(labelText: '現場', prefixIcon: Icon(Icons.location_city_outlined)),
                            items: _sites
                                .map((site) => DropdownMenuItem<String>(
                                      value: site['id'] as String,
                                      child: Text(site['name'].toString()),
                                    ))
                                .toList(),
                            onChanged: _saving ? null : (value) => setState(() => _siteId = value),
                          ),
                          if (_selectedSite != null) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_siteLocationText(_selectedSite!)),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _saving ? null : _setSelectedSiteLocation,
                                icon: const Icon(Icons.my_location),
                                label: const Text('この現場の基準位置を現在地で登録'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _eventType,
                            decoration: const InputDecoration(labelText: '確認', prefixIcon: Icon(Icons.schedule_outlined)),
                            items: const [
                              DropdownMenuItem(value: 'clock_in', child: Text('出勤')),
                              DropdownMenuItem(value: 'clock_out', child: Text('退勤')),
                            ],
                            onChanged: _saving ? null : (value) => setState(() => _eventType = value ?? 'clock_in'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _noteController,
                            enabled: !_saving,
                            decoration: const InputDecoration(labelText: 'メモ（任意）', prefixIcon: Icon(Icons.notes_outlined)),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _saving || _workerId == null || _siteId == null ? null : _confirm,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(_eventType == 'clock_in' ? Icons.login : Icons.logout),
                              label: Text(_saving ? '確認中…' : (_eventType == 'clock_in' ? '出勤を確認する' : '退勤を確認する')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('最近の確認', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_recent.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('確認履歴はまだありません。')))
                  else
                    for (final item in _recent)
                      Card(
                        child: ListTile(
                          leading: Icon(item['event_type'] == 'clock_in' ? Icons.login : Icons.logout),
                          title: Text('${_workerName(item)} / ${_siteName(item)}'),
                          subtitle: Text('${_eventLabel(item['event_type'])} ・ ${_modeLabel(item['verification_mode'])}\n${_statusLabel(item)}'),
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
      if (site['id'] == id) return site;
    }
    return null;
  }

  Future<void> _saveMode() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.saveSettings(mode: _mode, proximityRadiusM: _radiusM);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('確認方法を保存しました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('設定を保存できませんでした: $e')));
    }
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw StateError('端末の位置情報サービスをONにしてください。');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('位置情報の許可が必要です。');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('位置情報が常に拒否されています。端末の設定からこのアプリの位置情報を許可してください。');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('現場の基準位置を登録しました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('現場位置を登録できませんでした: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    final repository = _repository;
    final workerId = _workerId;
    final siteId = _siteId;
    if (repository == null || workerId == null || siteId == null) return;

    setState(() => _saving = true);
    try {
      double? latitude;
      double? longitude;
      double? accuracy;
      double? distance;
      var proximityStatus = 'not_checked';
      Uint8List? photoBytes;
      String? photoFilename;

      if (_mode != 'manual') {
        final position = await _currentPosition();
        latitude = position.latitude;
        longitude = position.longitude;
        accuracy = position.accuracy;

        final site = _selectedSite;
        final siteLatitude = _asDouble(site?['latitude']);
        final siteLongitude = _asDouble(site?['longitude']);
        if (siteLatitude == null || siteLongitude == null) {
          proximityStatus = 'site_location_missing';
        } else {
          distance = Geolocator.distanceBetween(
            latitude,
            longitude,
            siteLatitude,
            siteLongitude,
          );
          proximityStatus = distance <= _radiusM ? 'near_site' : 'outside_radius';
        }
      }

      if (_mode == 'location_photo') {
        final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (photo == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('写真撮影をキャンセルしたため、確認は登録していません。')));
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
      _noteController.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_eventType == 'clock_in' ? '出勤を確認しました' : '退勤を確認しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('確認を登録できませんでした: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _modeDescription(String mode) {
    switch (mode) {
      case 'location':
        return '確認時に現在地を1回だけ取得して記録します。';
      case 'location_photo':
        return '確認時に現在地を1回だけ取得し、その場で写真を1枚撮影します。';
      default:
        return '位置情報や写真を使わず、本人の操作だけで確認します。';
    }
  }

  String _modeLabel(Object? mode) {
    switch (mode) {
      case 'location':
        return '位置情報';
      case 'location_photo':
        return '位置情報＋写真';
      default:
        return '手動';
    }
  }

  String _eventLabel(Object? eventType) => eventType == 'clock_out' ? '退勤' : '出勤';

  String _workerName(Map<String, dynamic> item) {
    final worker = item['workers'];
    return worker is Map ? worker['name']?.toString() ?? '' : '';
  }

  String _siteName(Map<String, dynamic> item) {
    final site = item['sites'];
    return site is Map ? site['name']?.toString() ?? '' : '';
  }

  String _statusLabel(Map<String, dynamic> item) {
    switch (item['proximity_status']) {
      case 'near_site':
        final distance = _asDouble(item['distance_to_site_m']);
        return distance == null ? '現場付近で確認' : '現場付近で確認（約${distance.round()}m）';
      case 'outside_radius':
        final distance = _asDouble(item['distance_to_site_m']);
        return distance == null ? '基準範囲外' : '基準範囲外（約${distance.round()}m）';
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
    return '基準位置: 登録済み / 判定半径 ${_radiusM}m';
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
