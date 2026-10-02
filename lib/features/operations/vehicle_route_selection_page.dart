import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

enum VehicleRouteSelectionMode { vehicle, route }

class VehicleRouteSelectionPage extends StatefulWidget {
  const VehicleRouteSelectionPage({
    super.key,
    required this.mode,
  });

  final VehicleRouteSelectionMode mode;

  @override
  State<VehicleRouteSelectionPage> createState() =>
      _VehicleRouteSelectionPageState();
}

class _VehicleRouteSelectionPageState
    extends State<VehicleRouteSelectionPage> {
  final _repository = VehicleRouteRepository.maybeCreate();

  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _routes = const [];
  String? _vehicleId;
  String? _routeId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _vehicleMode => widget.mode == VehicleRouteSelectionMode.vehicle;

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
        _error = _vehicleMode
            ? '車両選択を利用できません。'
            : 'ルート選択を利用できません。';
      });
      return;
    }

    try {
      final values = await Future.wait([
        repository.vehicles(activeOnly: true),
        repository.routes(activeOnly: true),
        repository.loadTodaySelection(),
      ]);
      final selection = values[2] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
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
    if (repository == null || _saving) return;

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
        title: Text(
          _vehicleMode ? '車両の選択' : 'ルートの選択',
          style: const TextStyle(fontWeight: FontWeight.w900),
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
                      if (_vehicleMode) ...[
                        const Text(
                          '車両は勤務先とは別です。現場1か所でもルートでも、日報へ利用車両を記録するために選択します。',
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
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
