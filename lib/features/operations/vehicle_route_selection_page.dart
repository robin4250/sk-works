import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

enum VehicleRouteSelectionMode { vehicle, route }

class VehicleRouteSelectionPage extends StatefulWidget {
  const VehicleRouteSelectionPage({super.key, required this.mode, this.access});

  final VehicleRouteSelectionMode mode;
  final VehicleRouteSelectionAccess? access;

  @override
  State<VehicleRouteSelectionPage> createState() =>
      _VehicleRouteSelectionPageState();
}

class _VehicleRouteSelectionPageState extends State<VehicleRouteSelectionPage> {
  late final VehicleRouteSelectionAccess? _repository =
      widget.access ?? VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _routes = const [];
  String? _vehicleId;
  String? _routeId;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _loadedActorId;

  bool get _vehicleMode => widget.mode == VehicleRouteSelectionMode.vehicle;

  bool get _missingSelection {
    final id = _vehicleMode ? _vehicleId : _routeId;
    final options = _vehicleMode ? _vehicles : _routes;
    return id != null && !options.any((row) => row['id'] == id);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_saving || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _loading = false;
        _error = _vehicleMode ? '車両選択を利用できません。' : 'ルート選択を利用できません。';
      });
      return;
    }

    final actorId = repository.selectionActorId;
    try {
      final values = await Future.wait([
        _vehicleMode
            ? repository.vehicles(activeOnly: true)
            : Future.value(<Map<String, dynamic>>[]),
        !_vehicleMode
            ? repository.routes(activeOnly: true)
            : Future.value(<Map<String, dynamic>>[]),
        repository.loadTodaySelection(),
      ]);
      final selection = values[2] as Map<String, dynamic>;
      if (!mounted) return;
      if (actorId == null || repository.selectionActorId != actorId) {
        throw StateError('ログイン情報が変わりました。再読み込みしてください。');
      }
      setState(() {
        _loadedActorId = actorId;
        _vehicles = values[0] as List<Map<String, dynamic>>;
        _routes = values[1] as List<Map<String, dynamic>>;
        _vehicleId = selection['vehicle_id']?.toString();
        _routeId = selection['route_assignment_id']?.toString();
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
    final repository = _repository;
    if (repository == null ||
        _saving ||
        _loading ||
        _error != null ||
        _missingSelection) {
      return;
    }
    if (_loadedActorId == null ||
        repository.selectionActorId != _loadedActorId) {
      setState(() => _error = 'ログイン情報が変わりました。再読み込みしてください。');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_vehicleMode) {
        await repository.saveTodayVehicleSelection(_vehicleId);
      } else {
        await repository.saveTodayRouteSelection(_routeId);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存できませんでした: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _vehicleMode ? '車両の選択' : 'ルートの選択',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('再読み込み'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_vehicleMode) ...[
                    const Text(
                      '車両は勤務先とは別です。現場1か所でもルートでも、日報へ利用車両を記録するために選択します。',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(_vehicleId),
                      isExpanded: true,
                      initialValue: _vehicleId,
                      decoration: const InputDecoration(
                        labelText: '車両',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('車両を使わない'),
                        ),
                        if (_missingSelection)
                          DropdownMenuItem<String?>(
                            value: _vehicleId,
                            enabled: false,
                            child: const Text(
                              '選択済みの車両は現在利用できません',
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  ] else ...[
                    const Text(
                      '複数地点を回る日の勤務先です。車を使わない徒歩・電車等のルートでも登録できます。固定現場とルートは同時選択できません。',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      key: ValueKey(_routeId),
                      isExpanded: true,
                      initialValue: _routeId,
                      decoration: const InputDecoration(
                        labelText: 'ルート',
                        prefixIcon: Icon(Icons.route_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('ルートを使わない'),
                        ),
                        if (_missingSelection)
                          DropdownMenuItem<String?>(
                            value: _routeId,
                            enabled: false,
                            child: const Text(
                              '選択済みのルートは現在利用できません',
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  ],
                  if (_missingSelection) ...[
                    const SizedBox(height: 12),
                    const Text('保存済みの選択は保持しています。利用できる項目を選び直すか、使わないを選択してください。'),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving || _missingSelection ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_saving ? '保存中…' : '確定して保存'),
                  ),
                ],
              ),
      ),
    );
  }
}
