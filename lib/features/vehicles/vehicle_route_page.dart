import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

enum _VehicleRouteTab { vehicles, routes }

class VehicleRoutePage extends StatefulWidget {
  const VehicleRoutePage({super.key});

  @override
  State<VehicleRoutePage> createState() => _VehicleRoutePageState();
}

class _VehicleRoutePageState extends State<VehicleRoutePage> {
  final _repository = VehicleRouteRepository.maybeCreate();

  _VehicleRouteTab _tab = _VehicleRouteTab.vehicles;
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _drivers = [];
  bool _canManageVehicles = false;
  bool _canManageRoutes = false;
  bool _loading = true;
  String? _error;

  bool get _canManage =>
      _tab == _VehicleRouteTab.vehicles ? _canManageVehicles : _canManageRoutes;

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
        _error = '車両・ルート管理を利用できません。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await Future.wait([
        repository.loadVehicles(),
        repository.loadRoutes(),
        repository.loadSites(),
        repository.loadDrivers(),
        repository.managementPermissions(),
      ]);
      final permissions = values[4] as ({bool vehicles, bool routes});
      if (!mounted) return;
      setState(() {
        _vehicles = values[0] as List<Map<String, dynamic>>;
        _routes = values[1] as List<Map<String, dynamic>>;
        _sites = values[2] as List<Map<String, dynamic>>;
        _drivers = values[3] as List<Map<String, dynamic>>;
        _canManageVehicles = permissions.vehicles;
        _canManageRoutes = permissions.routes;
        _loading = false;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '車両・ルート',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _loading || !_canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: _tab == _VehicleRouteTab.vehicles
                  ? () => _editVehicle()
                  : () => _editRoute(),
              icon: const Icon(Icons.add),
              label: Text(
                _tab == _VehicleRouteTab.vehicles ? '車両を追加' : 'ルートを追加',
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<_VehicleRouteTab>(
                            segments: const [
                              ButtonSegment(
                                value: _VehicleRouteTab.vehicles,
                                icon: Icon(Icons.directions_car_outlined),
                                label: Text('車両'),
                              ),
                              ButtonSegment(
                                value: _VehicleRouteTab.routes,
                                icon: Icon(Icons.route_outlined),
                                label: Text('ルート'),
                              ),
                            ],
                            selected: {_tab},
                            onSelectionChanged: (value) {
                              setState(() => _tab = value.first);
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: _tab == _VehicleRouteTab.vehicles
                            ? _vehicleList()
                            : _routeList(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _vehicleList() {
    if (_vehicles.isEmpty) {
      return const Center(child: Text('車両はまだ登録されていません'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: _vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final vehicle = _vehicles[index];
        final active = vehicle['is_active'] == true;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              child: Icon(
                active
                    ? Icons.directions_car_outlined
                    : Icons.pause_circle_outline,
              ),
            ),
            title: Text(
              vehicle['display_name']?.toString() ?? '車両',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                vehicle['vehicle_type']?.toString(),
                vehicle['registration_number']?.toString(),
                if (!active) '休止中',
              ]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' / '),
            ),
            trailing: _canManageVehicles
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: _canManageVehicles
                ? () => _showVehicleActions(vehicle)
                : null,
          ),
        );
      },
    );
  }

  Widget _routeList() {
    if (_routes.isEmpty) {
      return const Center(child: Text('ルートはまだ登録されていません'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final route = _routes[index];
        final active = route['is_active'] == true;
        final vehicle = route['vehicles'] is Map
            ? (route['vehicles'] as Map)['display_name']?.toString()
            : null;
        final site = route['sites'] is Map
            ? (route['sites'] as Map)['name']?.toString()
            : null;
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              child: Icon(active ? Icons.route_outlined : Icons.pause_outlined),
            ),
            title: Text(
              route['route_name']?.toString() ?? 'ルート',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                _displayDate(route['service_date']?.toString()),
                site,
                vehicle,
                route['driver_name']?.toString(),
                if (!active) '休止中',
              ]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' / '),
            ),
            trailing:
                _canManageRoutes ? const Icon(Icons.chevron_right) : null,
            onTap:
                _canManageRoutes ? () => _showRouteActions(route) : null,
          ),
        );
      },
    );
  }

  Future<void> _showVehicleActions(Map<String, dynamic> vehicle) async {
    final active = vehicle['is_active'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('変更'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: Icon(
                active ? Icons.pause_circle_outline : Icons.play_circle_outline,
              ),
              title: Text(active ? '休止' : '利用を再開'),
              onTap: () => Navigator.pop(sheetContext, 'active'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _editVehicle(vehicle);
    } else if (action == 'active') {
      await _confirmVehicleActive(vehicle, !active);
    }
  }

  Future<void> _showRouteActions(Map<String, dynamic> route) async {
    final active = route['is_active'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('変更'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: Icon(
                active ? Icons.pause_circle_outline : Icons.play_circle_outline,
              ),
              title: Text(active ? '休止' : '利用を再開'),
              onTap: () => Navigator.pop(sheetContext, 'active'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      await _editRoute(route);
    } else if (action == 'active') {
      await _confirmRouteActive(route, !active);
    }
  }

  Future<void> _confirmVehicleActive(
    Map<String, dynamic> vehicle,
    bool active,
  ) async {
    final confirmed = await _confirm(
      title: active ? '車両の利用再開' : '車両休止の確認',
      message: active
          ? '「${vehicle['display_name']}」の利用を再開します。'
          : '「${vehicle['display_name']}」を休止します。過去のルート履歴は残ります。',
      confirmLabel: active ? '再開する' : '休止する',
    );
    if (!confirmed || _repository == null) return;
    await _repository!.setVehicleActive(vehicle['id'].toString(), active);
    await _load();
  }

  Future<void> _confirmRouteActive(
    Map<String, dynamic> route,
    bool active,
  ) async {
    final confirmed = await _confirm(
      title: active ? 'ルートの利用再開' : 'ルート休止の確認',
      message: active
          ? '「${route['route_name']}」の利用を再開します。'
          : '「${route['route_name']}」を休止します。履歴は削除しません。',
      confirmLabel: active ? '再開する' : '休止する',
    );
    if (!confirmed || _repository == null) return;
    await _repository!.setRouteActive(route['id'].toString(), active);
    await _load();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editVehicle([Map<String, dynamic>? vehicle]) async {
    final repository = _repository;
    if (repository == null) return;
    final name = TextEditingController(
      text: vehicle?['display_name']?.toString() ?? '',
    );
    final registration = TextEditingController(
      text: vehicle?['registration_number']?.toString() ?? '',
    );
    final type = TextEditingController(
      text: vehicle?['vehicle_type']?.toString() ?? '',
    );
    final capacity = TextEditingController(
      text: vehicle?['capacity']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: vehicle?['notes']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(vehicle == null ? '車両を追加' : '車両を変更'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '車両名 *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: registration,
                decoration: const InputDecoration(labelText: '登録番号'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: type,
                decoration: const InputDecoration(labelText: '車種・区分'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '定員'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '備考'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('内容を確認'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final confirmed = await _confirm(
      title: vehicle == null ? '車両登録の確認' : '車両変更の確認',
      message: '車両名: ${name.text.trim()}\n登録番号: ${registration.text.trim().isEmpty ? '未入力' : registration.text.trim()}',
      confirmLabel: vehicle == null ? '登録する' : '変更する',
    );
    if (!confirmed) return;

    await repository.saveVehicle(
      id: vehicle?['id']?.toString(),
      displayName: name.text,
      registrationNumber: registration.text,
      vehicleType: type.text,
      capacity: int.tryParse(capacity.text.trim()),
      notes: notes.text,
      isActive: vehicle?['is_active'] != false,
    );
    await _load();
  }

  Future<void> _editRoute([Map<String, dynamic>? route]) async {
    final repository = _repository;
    if (repository == null) return;

    var date = DateTime.tryParse(route?['service_date']?.toString() ?? '') ??
        DateTime.now();
    final routeName = TextEditingController(
      text: route?['route_name']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: route?['notes']?.toString() ?? '',
    );
    String? vehicleId = route?['vehicle_id']?.toString();
    String? siteId = route?['site_id']?.toString();
    String? driverId = route?['driver_user_id']?.toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(route == null ? 'ルートを追加' : 'ルートを変更'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('運行日'),
                  subtitle: Text(_displayDate(_date(date))),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                TextField(
                  controller: routeName,
                  decoration: const InputDecoration(labelText: 'ルート名 *'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: vehicleId,
                  decoration: const InputDecoration(labelText: '車両'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未指定'),
                    ),
                    for (final vehicle
                        in _vehicles.where((row) => row['is_active'] == true))
                      DropdownMenuItem<String?>(
                        value: vehicle['id'].toString(),
                        child: Text(vehicle['display_name'].toString()),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => vehicleId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: siteId,
                  decoration: const InputDecoration(labelText: '現場'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未指定'),
                    ),
                    for (final site in _sites)
                      DropdownMenuItem<String?>(
                        value: site['id'].toString(),
                        child: Text(site['name'].toString()),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => siteId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: driverId,
                  decoration: const InputDecoration(labelText: '運転者'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未指定'),
                    ),
                    for (final driver in _drivers)
                      DropdownMenuItem<String?>(
                        value: driver['id'].toString(),
                        child: Text(driver['name'].toString()),
                      ),
                  ],
                  onChanged: (value) => setDialogState(() => driverId = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: '備考'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (routeName.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('内容を確認'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final confirmed = await _confirm(
      title: route == null ? 'ルート登録の確認' : 'ルート変更の確認',
      message: '運行日: ${_displayDate(_date(date))}\nルート名: ${routeName.text.trim()}',
      confirmLabel: route == null ? '登録する' : '変更する',
    );
    if (!confirmed) return;

    await repository.saveRoute(
      id: route?['id']?.toString(),
      serviceDate: date,
      routeName: routeName.text,
      vehicleId: vehicleId,
      siteId: siteId,
      driverUserId: driverId,
      notes: notes.text,
      isActive: route?['is_active'] != false,
    );
    await _load();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _displayDate(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.replaceAll('-', '/');
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}
