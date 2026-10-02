// ignore_for_file: prefer_interpolation_to_compose_strings, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import 'route_editor_page.dart';
import 'vehicle_editor_page.dart';
import 'vehicle_route_repository.dart';

class VehicleRoutePage extends StatefulWidget {
  const VehicleRoutePage({super.key});

  @override
  State<VehicleRoutePage> createState() => _VehicleRoutePageState();
}

class _VehicleRoutePageState extends State<VehicleRoutePage> {
  final _repository = VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _routes = const [];
  List<Map<String, dynamic>> _sites = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _partners = const [];
  bool _canManageVehicles = false;
  bool _canManageRoutes = false;
  bool _loading = true;
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
        _error = '車両・ルート情報を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        repository.vehicles(),
        repository.routes(),
        repository.permissions(),
        repository.sites(),
        repository.customers(),
        repository.partners(),
      ]);
      final permissions = values[2] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _vehicles = values[0] as List<Map<String, dynamic>>;
        _routes = values[1] as List<Map<String, dynamic>>;
        _sites = values[3] as List<Map<String, dynamic>>;
        _customers = values[4] as List<Map<String, dynamic>>;
        _partners = values[5] as List<Map<String, dynamic>>;
        _canManageVehicles = permissions['can_manage_vehicles'] == true;
        _canManageRoutes = permissions['can_manage_routes'] == true;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '車両・ルート',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.directions_car_outlined), text: '車両'),
              Tab(icon: Icon(Icons.route_outlined), text: 'ルート'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _reload)
                : TabBarView(
                    children: [
                      _vehicleList(),
                      _routeList(),
                    ],
                  ),
      ),
    );
  }

  Widget _vehicleList() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '表示名・車両番号・走行距離・保管場所（駐車場住所）と、車検証・自賠責保険・任意保険証書を管理します。',
          ),
          const SizedBox(height: 12),
          if (_canManageVehicles)
            FilledButton.icon(
              onPressed: () => _openVehicleEditor(),
              icon: const Icon(Icons.add),
              label: const Text('車両を登録'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          const SizedBox(height: 12),
          if (_vehicles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('登録された車両はありません'),
              ),
            )
          else
            for (final row in _vehicles)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      row['is_active'] == true
                          ? Icons.directions_car_outlined
                          : Icons.pause_circle_outline,
                    ),
                  ),
                  title: Text(
                    row['display_name']?.toString() ?? '車両',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    [
                      if ((row['registration_number']?.toString() ?? '').isNotEmpty)
                        '車両番号 ' + row['registration_number'].toString(),
                      '走行距離 ' + _km(row['odometer_km']) + ' km',
                      if ((row['storage_address']?.toString() ?? '').isNotEmpty)
                        '駐車場 ' + row['storage_address'].toString(),
                      _documentSummary(row),
                      if (row['is_active'] != true) '休止中',
                    ].join(' / '),
                  ),
                  isThreeLine: true,
                  trailing: _canManageVehicles
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _openVehicleEditor(row);
                            if (value == 'active') _toggleVehicle(row);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('内容を変更'),
                            ),
                            PopupMenuItem(
                              value: 'active',
                              child: Text(
                                row['is_active'] == true ? '休止する' : '再開する',
                              ),
                            ),
                          ],
                        )
                      : null,
                  onTap: _canManageVehicles
                      ? () => _openVehicleEditor(row)
                      : null,
                ),
              ),
        ],
      );

  Widget _routeList() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'ルート名と、現場・登録車両の駐車場・住所を必要な数だけ順番に登録できます。',
          ),
          const SizedBox(height: 12),
          if (_canManageRoutes)
            FilledButton.icon(
              onPressed: () => _openRouteEditor(),
              icon: const Icon(Icons.add_road_outlined),
              label: const Text('ルートを登録'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          const SizedBox(height: 12),
          if (_routes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('登録されたルートはありません'),
              ),
            )
          else
            for (final row in _routes)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      row['is_active'] == true
                          ? Icons.route_outlined
                          : Icons.pause_circle_outline,
                    ),
                  ),
                  title: Text(
                    row['route_name']?.toString() ?? 'ルート',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    [
                      _routeStopSummary(row),
                      if ((row['notes']?.toString() ?? '').isNotEmpty)
                        row['notes'].toString(),
                      if (row['is_active'] != true) '休止中',
                    ].where((text) => text.isNotEmpty).join(' / '),
                  ),
                  isThreeLine: true,
                  trailing: _canManageRoutes
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') _openRouteEditor(row);
                            if (value == 'active') _toggleRoute(row);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('内容を変更'),
                            ),
                            PopupMenuItem(
                              value: 'active',
                              child: Text(
                                row['is_active'] == true ? '休止する' : '再開する',
                              ),
                            ),
                          ],
                        )
                      : null,
                  onTap:
                      _canManageRoutes ? () => _openRouteEditor(row) : null,
                ),
              ),
        ],
      );

  Future<void> _openVehicleEditor([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VehicleEditorPage(vehicle: row),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _openRouteEditor([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RouteEditorPage(
          route: row,
          sites: _sites,
          vehicles: _vehicles,
        ),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _toggleVehicle(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final active = row['is_active'] == true;
    final name = row['display_name']?.toString() ?? '車両';
    if (!await _confirm(
      active ? '車両を休止しますか？' : '車両を再開しますか？',
      active ? name + 'を休止します。履歴は残ります。' : name + 'を再開します。',
    )) return;
    await repository.setVehicleActive(row['id'].toString(), !active);
    await _reload();
  }

  Future<void> _toggleRoute(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final active = row['is_active'] == true;
    final name = row['route_name']?.toString() ?? 'ルート';
    if (!await _confirm(
      active ? 'ルートを休止しますか？' : 'ルートを再開しますか？',
      active ? name + 'を休止します。履歴は残ります。' : name + 'を再開します。',
    )) return;
    await repository.setRouteActive(row['id'].toString(), !active);
    await _reload();
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('確定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _load();
  }

  String _documentSummary(Map<String, dynamic> row) {
    var count = 0;
    if ((row['registration_document_path']?.toString() ?? '').isNotEmpty) {
      count++;
    }
    if ((row['compulsory_insurance_path']?.toString() ?? '').isNotEmpty) {
      count++;
    }
    if ((row['voluntary_insurance_path']?.toString() ?? '').isNotEmpty) {
      count++;
    }
    return '書類 ' + count.toString() + '/3';
  }

  String _routeStopSummary(Map<String, dynamic> row) {
    final raw = row['route_stops'];
    if (raw is! List || raw.isEmpty) return '地点未登録';
    final names = <String>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final site = value['sites'];
      final siteName =
          site is Map ? site['name']?.toString().trim() ?? '' : '';
      final label = value['source_label']?.toString().trim() ?? '';
      final address = value['address']?.toString().trim() ?? '';
      if (label.isNotEmpty) {
        names.add(label);
      } else if (siteName.isNotEmpty) {
        names.add(siteName);
      } else if (address.isNotEmpty) {
        names.add(address);
      }
    }
    return names.isEmpty ? '地点未登録' : names.join(' → ');
  }

  String _km(Object? value) {
    final number = (value as num?)?.toDouble() ??
        double.tryParse(value?.toString() ?? '') ??
        0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(1);
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
