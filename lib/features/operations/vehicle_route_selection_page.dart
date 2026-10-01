import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

class VehicleRouteSelectionPage extends StatefulWidget {
  const VehicleRouteSelectionPage({super.key});

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
        _error = '車両・ルート選択を利用できません。';
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('車両とルートを保存しますか？'),
        content: const Text(
          '今日の出勤・退勤と日報へ、この選択を引き継ぎます。未選択のままでも保存できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await repository.saveTodaySelection(
        vehicleId: _vehicleId,
        routeId: _routeId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存できませんでした: ' + error.toString())),
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
          '車両とルートの選択',
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
                            child: Text('未選択'),
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
                      const SizedBox(height: 14),
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
                            child: Text('未選択'),
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
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _vehicleId = null;
                                  _routeId = null;
                                }),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('車両とルートの選択を解除'),
                      ),
                      const SizedBox(height: 10),
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
