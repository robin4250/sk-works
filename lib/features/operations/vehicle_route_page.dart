import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

class VehicleRoutePage extends StatefulWidget {
  const VehicleRoutePage({super.key});

  @override
  State<VehicleRoutePage> createState() => _VehicleRoutePageState();
}

class _VehicleRoutePageState extends State<VehicleRoutePage> {
  final _repository = VehicleRouteRepository.maybeCreate();
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _drivers = [];
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
        repository.drivers(),
      ]);
      final permissions = values[2] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _vehicles = values[0] as List<Map<String, dynamic>>;
        _routes = values[1] as List<Map<String, dynamic>>;
        _sites = values[3] as List<Map<String, dynamic>>;
        _drivers = values[4] as List<Map<String, dynamic>>;
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
          title: const Text('車両・ルート'),
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
                ? _errorView()
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
          const Text('全従業員が閲覧・利用できます。休止した車両も履歴のため残ります。'),
          const SizedBox(height: 12),
          if (_canManageVehicles)
            FilledButton.icon(
              onPressed: () => _editVehicle(),
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
                      row['registration_number']?.toString(),
                      row['vehicle_type']?.toString(),
                      if (row['is_active'] != true) '休止中',
                    ].whereType<String>().where((v) => v.isNotEmpty).join(' / '),
                  ),
                  trailing: _canManageVehicles
                      ? PopupMenuButton<String>(
                          tooltip: '車両の操作',
                          onSelected: (value) {
                            if (value == 'edit') _editVehicle(row);
                            if (value == 'active') _setVehicleActive(row);
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
                  onTap: _canManageVehicles ? () => _editVehicle(row) : null,
                ),
              ),
        ],
      );

  Widget _routeList() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('配車・現場移動の予定を共有します。休止しても過去の履歴は残ります。'),
          const SizedBox(height: 12),
          if (_canManageRoutes)
            FilledButton.icon(
              onPressed: () => _editRoute(),
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
                      row['service_date']?.toString(),
                      if (row['is_active'] != true) '休止中',
                    ].whereType<String>().where((v) => v.isNotEmpty).join(' / '),
                  ),
                  trailing: _canManageRoutes
                      ? PopupMenuButton<String>(
                          tooltip: 'ルートの操作',
                          onSelected: (value) {
                            if (value == 'edit') _editRoute(row);
                            if (value == 'active') _setRouteActive(row);
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
                  onTap: _canManageRoutes ? () => _editRoute(row) : null,
                ),
              ),
        ],
      );

  Future<void> _editVehicle([Map<String, dynamic>? row]) async {
    final repository = _repository;
    if (repository == null) return;
    final name = TextEditingController(text: row?['display_name']?.toString());
    final registration =
        TextEditingController(text: row?['registration_number']?.toString());
    final type = TextEditingController(text: row?['vehicle_type']?.toString());
    final capacity =
        TextEditingController(text: row?['capacity']?.toString());
    final notes = TextEditingController(text: row?['notes']?.toString());
    final active = row?['is_active'] != false;

    final result = await showDialog<_VehicleDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(row == null ? '車両を登録' : '車両を変更'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '表示名')),
              TextField(controller: registration, decoration: const InputDecoration(labelText: '登録番号')),
              TextField(controller: type, decoration: const InputDecoration(labelText: '車種')),
              TextField(controller: capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '定員')),
              TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: '備考')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                dialogContext,
                _VehicleDraft(
                  name: name.text,
                  registration: registration.text,
                  type: type.text,
                  capacity: int.tryParse(capacity.text),
                  notes: notes.text,
                ),
              );
            },
            child: const Text('内容を確認'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;

    final confirmed = await _confirm(
      title: row == null ? '車両登録の確認' : '車両変更の確認',
      body: '「${result.name.trim()}」の内容を保存します。',
      action: '保存する',
    );
    if (!confirmed) return;

    await repository.saveVehicle(
      id: row?['id']?.toString(),
      name: result.name,
      registrationNumber: result.registration,
      vehicleType: result.type,
      capacity: result.capacity,
      notes: result.notes,
    );
    if (row != null && active != (row['is_active'] == true)) {
      await repository.setVehicleActive(row['id'].toString(), active);
    }
    await _reload();
  }

  Future<void> _editRoute([Map<String, dynamic>? row]) async {
    final repository = _repository;
    if (repository == null) return;
    final name = TextEditingController(text: row?['route_name']?.toString());
    final date = TextEditingController(
      text: row?['service_date']?.toString() ??
          DateTime.now().toIso8601String().substring(0, 10),
    );
    final notes = TextEditingController(text: row?['notes']?.toString());
    var vehicleId = row?['vehicle_id']?.toString() ?? '';
    var siteId = row?['site_id']?.toString() ?? '';
    var driverUserId = row?['driver_user_id']?.toString() ?? '';

    final result = await showDialog<_RouteDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(row == null ? 'ルートを登録' : 'ルートを変更'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: date,
                  decoration: const InputDecoration(labelText: '運行日（YYYY-MM-DD）'),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'ルート名'),
                ),
                DropdownButtonFormField<String>(
                  value: vehicleId,
                  decoration: const InputDecoration(labelText: '車両'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未指定')),
                    for (final vehicle in _vehicles)
                      DropdownMenuItem(
                        value: vehicle['id']?.toString() ?? '',
                        child: Text(vehicle['display_name']?.toString() ?? '車両'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => vehicleId = value ?? ''),
                ),
                DropdownButtonFormField<String>(
                  value: siteId,
                  decoration: const InputDecoration(labelText: '現場'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未指定')),
                    for (final site in _sites)
                      DropdownMenuItem(
                        value: site['id']?.toString() ?? '',
                        child: Text(site['name']?.toString() ?? '現場'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => siteId = value ?? ''),
                ),
                DropdownButtonFormField<String>(
                  value: driverUserId,
                  decoration: const InputDecoration(labelText: '運転者'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('未指定')),
                    for (final driver in _drivers)
                      DropdownMenuItem(
                        value: driver['user_id']?.toString() ?? '',
                        child: Text(driver['name']?.toString() ?? '従業員'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => driverUserId = value ?? ''),
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '備考'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = DateTime.tryParse(date.text.trim());
                if (name.text.trim().isEmpty || parsed == null) return;
                Navigator.pop(
                  dialogContext,
                  _RouteDraft(
                    date: parsed,
                    name: name.text,
                    notes: notes.text,
                    vehicleId: vehicleId,
                    siteId: siteId,
                    driverUserId: driverUserId,
                  ),
                );
              },
              child: const Text('内容を確認'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    final confirmed = await _confirm(
      title: row == null ? 'ルート登録の確認' : 'ルート変更の確認',
      body: '「${result.name.trim()}」を${result.date.toIso8601String().substring(0, 10)}のルートとして保存します。',
      action: '保存する',
    );
    if (!confirmed) return;

    await repository.saveRoute(
      id: row?['id']?.toString(),
      serviceDate: result.date,
      name: result.name,
      vehicleId: result.vehicleId,
      siteId: result.siteId,
      driverUserId: result.driverUserId,
      notes: result.notes,
    );
    await _reload();
  }

  Future<void> _setVehicleActive(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final active = row['is_active'] == true;
    final name = row['display_name']?.toString() ?? '車両';
    final confirmed = await _confirm(
      title: active ? '車両休止の確認' : '車両再開の確認',
      body: active
          ? '「$name」を休止します。過去のルート履歴は削除されません。'
          : '「$name」を再開します。',
      action: active ? '休止する' : '再開する',
    );
    if (!confirmed) return;
    await repository.setVehicleActive(row['id'].toString(), !active);
    await _reload();
  }

  Future<void> _setRouteActive(Map<String, dynamic> row) async {
    final repository = _repository;
    if (repository == null) return;
    final active = row['is_active'] == true;
    final name = row['route_name']?.toString() ?? 'ルート';
    final confirmed = await _confirm(
      title: active ? 'ルート休止の確認' : 'ルート再開の確認',
      body: active
          ? '「$name」を休止します。過去の運行履歴は削除されません。'
          : '「$name」を再開します。',
      action: active ? '休止する' : '再開する',
    );
    if (!confirmed) return;
    await repository.setRouteActive(row['id'].toString(), !active);
    await _reload();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reload, child: const Text('再試行')),
            ],
          ),
        ),
      );

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _load();
  }
}

class _VehicleDraft {
  const _VehicleDraft({
    required this.name,
    required this.registration,
    required this.type,
    required this.capacity,
    required this.notes,
  });
  final String name;
  final String registration;
  final String type;
  final int? capacity;
  final String notes;
}

class _RouteDraft {
  const _RouteDraft({
    required this.date,
    required this.name,
    required this.notes,
    required this.vehicleId,
    required this.siteId,
    required this.driverUserId,
  });
  final DateTime date;
  final String name;
  final String notes;
  final String vehicleId;
  final String siteId;
  final String driverUserId;
}
