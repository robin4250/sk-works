// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

enum VehicleRouteSelectionKind { vehicle, route }

class VehicleRouteSelectionPage extends StatefulWidget {
  const VehicleRouteSelectionPage({
    super.key,
    required this.kind,
  });

  final VehicleRouteSelectionKind kind;

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

  Future<void> _showRouteGuide() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('外回りのルートへ出勤'),
        content: const Text(
          '勤務先は「固定の1つの現場」か「外回りで複数地点を回るルート」のどちらか一方です。ルートを選ぶと、今日選択している固定現場は解除されます。ルート名が勤務先名として表示されます。',
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
    final repository = _repository;
    if (repository == null || _saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.kind == VehicleRouteSelectionKind.vehicle
              ? '車両を保存しますか？'
              : 'ルートを保存しますか？',
        ),
        content: Text(
          widget.kind == VehicleRouteSelectionKind.vehicle
              ? '車両は勤務先とは別の任意選択です。固定現場でもルート勤務でも、車両を使う場合だけ選択してください。日報へ引き継ぎます。'
              : 'ルートは外回りなど複数地点を回る日の勤務先です。車両を使わなくても選択できます。固定現場との同時選択はできません。',
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
      if (widget.kind == VehicleRouteSelectionKind.vehicle) {
        await repository.saveTodayVehicleSelection(_vehicleId);
      } else {
        await repository.saveTodayRouteSelection(_routeId);
      }
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
        title: Text(
          widget.kind == VehicleRouteSelectionKind.vehicle
              ? '車両の選択'
              : 'ルートの選択',
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
                      if (widget.kind == VehicleRouteSelectionKind.vehicle) ...[
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
                      ] else ...[
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
                            : (value) async {
                                if (value != null && value != _routeId) {
                                  await _showRouteGuide();
                                }
                                if (!mounted) return;
                                setState(() => _routeId = value);
                              },
                      ),
                      ],
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  if (widget.kind ==
                                      VehicleRouteSelectionKind.vehicle) {
                                    _vehicleId = null;
                                  } else {
                                    _routeId = null;
                                  }
                                }),
                        icon: const Icon(Icons.clear_all),
                        label: Text(
                          widget.kind == VehicleRouteSelectionKind.vehicle
                              ? '車両の選択を解除'
                              : 'ルートの選択を解除',
                        ),
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
