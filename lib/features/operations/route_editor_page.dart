// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import 'vehicle_route_repository.dart';

class RouteEditorPage extends StatefulWidget {
  const RouteEditorPage({
    super.key,
    required this.sites,
    required this.customers,
    required this.partners,
    required this.vehicles,
    this.route,
  });

  final List<Map<String, dynamic>> sites;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> partners;
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

  List<_StopChoice> get _choices {
    final result = <_StopChoice>[
      for (final site in widget.sites)
        _StopChoice(
          kind: 'site',
          id: site['id']?.toString() ?? '',
          label: '現場：${site['name']?.toString() ?? '現場'}',
          address: site['address']?.toString() ?? '',
          siteId: site['id']?.toString(),
        ),
      for (final customer in widget.customers)
        _StopChoice(
          kind: 'customer',
          id: customer['id']?.toString() ?? '',
          label:
              '取引会社：${(customer['billing_name']?.toString().trim().isNotEmpty ?? false) ? customer['billing_name'] : customer['name']}',
          address: customer['billing_address']?.toString() ?? '',
        ),
      for (final partner in widget.partners)
        _StopChoice(
          kind: 'partner',
          id: partner['id']?.toString() ?? '',
          label: '下請け会社：${partner['name']?.toString() ?? '会社'}',
          address: partner['address']?.toString() ?? '',
        ),
      for (final vehicle in widget.vehicles)
        if ((vehicle['parking_address']?.toString().trim() ?? '').isNotEmpty)
          _StopChoice(
            kind: 'parking',
            id: vehicle['id']?.toString() ?? '',
            label: '駐車場：${vehicle['display_name']?.toString() ?? '車両'}',
            address: vehicle['parking_address']?.toString() ?? '',
          ),
    ];
    return result.where((choice) => choice.id.isNotEmpty).toList();
  }

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
            final siteId = row['site_id']?.toString();
            final sourceKind = row['source_kind']?.toString();
            final sourceId = row['source_id']?.toString();
            return _StopDraft(
              siteId: siteId,
              sourceKind: sourceKind ?? (siteId != null ? 'site' : 'address'),
              sourceId: sourceId ?? siteId,
              sourceLabel: row['source_label']?.toString() ??
                  (site is Map ? site['name']?.toString() ?? '' : ''),
              address: row['address']?.toString() ??
                  (site is Map ? site['address']?.toString() ?? '' : ''),
            );
          }).toList()
        : <_StopDraft>[];

    if (_stops.isEmpty) _stops = [_StopDraft()];
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

  void _addStop() => setState(() => _stops.add(_StopDraft()));

  void _removeStop(int index) {
    if (_stops.length == 1) {
      setState(() => _stops[index].clear());
      return;
    }
    final removed = _stops.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  String? _selectedKey(_StopDraft stop) {
    final kind = stop.sourceKind;
    final id = stop.sourceId;
    if (kind == null || id == null || id.isEmpty || kind == 'address') {
      return null;
    }
    final key = '$kind:$id';
    return _choices.any((choice) => choice.key == key) ? key : null;
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
        'source_kind': stop.sourceKind ?? 'address',
        'source_id': stop.sourceId,
        'source_label': stop.sourceLabel?.trim().isEmpty == true
            ? null
            : stop.sourceLabel,
      });
    }

    if (_name.text.trim().isEmpty || stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ルート名と地点を1件以上登録してください'),
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
            'ルート地点',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text('現場・取引会社・下請け会社・駐車場を選ぶか、住所を直接入力できます。'),
          const SizedBox(height: 10),
          for (var i = 0; i < _stops.length; i++) _stopCard(i, _stops[i]),
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
                    initialValue: _selectedKey(stop),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '登録済み地点から選択',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('住所を直接入力'),
                      ),
                      for (final choice in _choices)
                        DropdownMenuItem<String?>(
                          value: choice.key,
                          child: Text(
                            choice.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value == null) {
                                stop.siteId = null;
                                stop.sourceKind = 'address';
                                stop.sourceId = null;
                                stop.sourceLabel = null;
                                stop.address.clear();
                                return;
                              }
                              final choice = _choices.firstWhere(
                                (item) => item.key == value,
                              );
                              stop.siteId = choice.siteId;
                              stop.sourceKind = choice.kind;
                              stop.sourceId = choice.id;
                              stop.sourceLabel = choice.label;
                              stop.address.text = choice.address;
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
              onChanged: (_) {
                if (_selectedKey(stop) != null) {
                  setState(() {
                    stop.siteId = null;
                    stop.sourceKind = 'address';
                    stop.sourceId = null;
                    stop.sourceLabel = null;
                  });
                }
              },
              decoration: const InputDecoration(
                labelText: '住所',
                hintText: '選択した地点の住所、または任意住所',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopChoice {
  const _StopChoice({
    required this.kind,
    required this.id,
    required this.label,
    required this.address,
    this.siteId,
  });

  final String kind;
  final String id;
  final String label;
  final String address;
  final String? siteId;

  String get key => '$kind:$id';
}

class _StopDraft {
  _StopDraft({
    this.siteId,
    this.sourceKind,
    this.sourceId,
    this.sourceLabel,
    String address = '',
  }) : address = TextEditingController(text: address);

  String? siteId;
  String? sourceKind;
  String? sourceId;
  String? sourceLabel;
  final TextEditingController address;

  void clear() {
    siteId = null;
    sourceKind = null;
    sourceId = null;
    sourceLabel = null;
    address.clear();
  }

  void dispose() {
    address.dispose();
  }
}
