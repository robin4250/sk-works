// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

class RouteEditorPage extends StatefulWidget {
  const RouteEditorPage({
    super.key,
    required this.sites,
    required this.vehicles,
    this.route,
  });

  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> vehicles;
  final Map<String, dynamic>? route;

  @override
  State<RouteEditorPage> createState() => _RouteEditorPageState();
}

class _RouteEditorPageState extends State<RouteEditorPage> {
  final _repository = VehicleRouteRepository.maybeCreate();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late List<_StopDraft> _stops;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.route?['route_name']?.toString() ?? '',
    );
    _notes = TextEditingController(
      text: widget.route?['notes']?.toString() ?? '',
    );

    final raw = widget.route?['route_stops'];
    _stops = raw is List
        ? raw.whereType<Map>().map((row) {
            final site = row['sites'];
            return _StopDraft(
              siteId: row['site_id']?.toString(),
              address: row['address']?.toString() ??
                  (site is Map ? site['address']?.toString() ?? '' : ''),
            );
          }).toList()
        : <_StopDraft>[];

    if (_stops.isEmpty) {
      _stops = [_StopDraft()];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    super.dispose();
  }

  void _addStop() {
    setState(() => _stops.add(_StopDraft()));
  }

  void _removeStop(int index) {
    if (_stops.length == 1) {
      setState(() => _stops[index].clear());
      return;
    }
    final removed = _stops.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    final repository = _repository;
    if (repository == null || _saving) return;

    final stops = <Map<String, String?>>[];
    for (final stop in _stops) {
      final siteId = stop.siteId?.trim();
      final address = stop.address.text.trim();
      if ((siteId == null || siteId.isEmpty) && address.isEmpty) continue;
      stops.add({
        'site_id': siteId,
        'address': address.isEmpty ? null : address,
      });
    }

    if (_name.text.trim().isEmpty || stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ルート名と、現場または住所を1件以上登録してください'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.route == null ? 'ルートを登録しますか？' : 'ルートを更新しますか？'),
        content: Text(
          _name.text.trim() +
              ' / 地点 ' +
              stops.length.toString() +
              '件',
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
      await repository.saveRoute(
        id: widget.route?['id']?.toString(),
        name: _name.text,
        notes: _notes.text,
        stops: stops,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ルートを保存できませんでした: ' + error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route == null ? 'ルートを登録' : 'ルートを変更'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'ルート名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '現場・駐車場の選択 または 住所',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text('地点は必要な数だけ追加できます。'),
          const SizedBox(height: 10),
          for (var i = 0; i < _stops.length; i++)
            _stopCard(i, _stops[i]),
          OutlinedButton.icon(
            onPressed: _saving ? null : _addStop,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('地点を追加'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '備考',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '確定して保存'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopCard(int index, _StopDraft stop) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  child: Text((index + 1).toString()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: stop.siteId,
                    decoration: const InputDecoration(
                      labelText: '現場名',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('現場・駐車場を選ばず住所を入力'),
                      ),
                      for (final vehicle in widget.vehicles)
                        if ((vehicle['storage_address']?.toString() ?? '').isNotEmpty)
                          DropdownMenuItem<String?>(
                            value: 'parking:' + vehicle['id'].toString(),
                            child: Text(
                              '駐車場：' +
                                  (vehicle['display_name']?.toString() ?? '車両'),
                            ),
                          ),
                      for (final site in widget.sites)
                        DropdownMenuItem<String?>(
                          value: site['id']?.toString(),
                          child: Text(site['name']?.toString() ?? '現場'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value != null && value.startsWith('parking:')) {
                                stop.siteId = null;
                                final vehicleId =
                                    value.substring('parking:'.length);
                                final vehicle = widget.vehicles.where(
                                  (row) => row['id']?.toString() == vehicleId,
                                );
                                if (vehicle.isNotEmpty) {
                                  stop.address.text =
                                      vehicle.first['storage_address']?.toString() ?? '';
                                }
                              } else {
                                stop.siteId = value;
                                if (value != null) {
                                  final site = widget.sites.where(
                                    (row) => row['id']?.toString() == value,
                                  );
                                  if (site.isNotEmpty) {
                                    stop.address.text =
                                        site.first['address']?.toString() ?? '';
                                  }
                                }
                              }
                            });
                          },
                  ),
                ),
                IconButton(
                  tooltip: '地点を削除',
                  onPressed: _saving ? null : () => _removeStop(index),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: stop.address,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: '住所',
                hintText: '現場・駐車場を選ばない場合はこちらを入力',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopDraft {
  _StopDraft({
    this.siteId,
    String address = '',
  }) : address = TextEditingController(text: address);

  String? siteId;
  final TextEditingController address;

  void clear() {
    siteId = null;
    address.clear();
  }

  void dispose() {
    address.dispose();
  }
}
