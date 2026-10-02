import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import 'site_map_repository.dart';

enum _MapLayer { sites, customers, partners, company, home, employeeHomes }

class SiteMapPage extends StatefulWidget {
  const SiteMapPage({
    super.key,
    this.allowEmployeeHomes = false,
  });

  final bool allowEmployeeHomes;

  @override
  State<SiteMapPage> createState() => _SiteMapPageState();
}

class _SiteMapPageState extends State<SiteMapPage> {
  final _repository = SiteMapRepository.maybeCreate();
  SiteMapWorkspace? _data;
  bool _loading = true;
  String? _error;
  final Set<_MapLayer> _layers = {
    _MapLayer.sites,
    _MapLayer.customers,
    _MapLayer.company,
    _MapLayer.home,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError('現場マップを利用できません');
      final value = await repository.load();
      if (!mounted) return;
      setState(() {
        _data = value;
        if (!value.canViewAll || !widget.allowEmployeeHomes) {
          _layers.remove(_MapLayer.employeeHomes);
        }
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

  Future<void> _mapAddress(
    Map<String, dynamic> row,
    String labelKey, {
    bool preferAddress = true,
  }) async {
    final address = row['address']?.toString().trim() ?? '';
    final lat = row['latitude'] as num?;
    final lon = row['longitude'] as num?;
    final query = preferAddress && address.isNotEmpty
        ? address
        : lat != null && lon != null
            ? '${lat.toDouble()},${lon.toDouble()}'
            : address;
    if (query.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Googleマップで開ける位置情報がありません')),
      );
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${row[labelKey]?.toString() ?? 'SKO'}をGoogleマップで開けませんでした',
          ),
        ),
      );
    }
  }

  List<Map<String, dynamic>> _selectedPlaces(SiteMapWorkspace data) {
    final places = <Map<String, dynamic>>[];
    if (_layers.contains(_MapLayer.sites)) places.addAll(data.sites);
    if (_layers.contains(_MapLayer.customers)) places.addAll(data.customers);
    if (_layers.contains(_MapLayer.partners)) places.addAll(data.partners);
    if (_layers.contains(_MapLayer.company) && data.company != null) {
      places.add(data.company!);
    }
    if (_layers.contains(_MapLayer.home) && data.home != null) {
      places.add(data.home!);
    }
    if (_layers.contains(_MapLayer.employeeHomes) &&
        data.canViewAll &&
        widget.allowEmployeeHomes) {
      places.addAll(data.employeeHomes);
    }
    return places.where((row) {
      final address = row['address']?.toString().trim() ?? '';
      final lat = row['latitude'] as num?;
      final lon = row['longitude'] as num?;
      return address.isNotEmpty || (lat != null && lon != null);
    }).toList(growable: false);
  }

  String _locationText(Map<String, dynamic> row) {
    final address = row['address']?.toString().trim() ?? '';
    if (address.isNotEmpty) return address;
    final lat = row['latitude'] as num?;
    final lon = row['longitude'] as num?;
    if (lat != null && lon != null) {
      return '${lat.toDouble()},${lon.toDouble()}';
    }
    return '';
  }

  Future<void> _openSelectedTogether() async {
    final data = _data;
    if (data == null) return;
    final selected = _selectedPlaces(data);
    Position? current;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        current = await Geolocator.getCurrentPosition();
      }
    } catch (_) {
      // Current location is supplemental. Saved pins can still open.
    }

    final points = <String>[
      if (current != null) '${current.latitude},${current.longitude}',
      ...selected.map(_locationText).where((value) => value.isNotEmpty),
    ];
    if (points.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('表示する地点を選択してください')),
      );
      return;
    }

    Uri uri;
    if (points.length == 1) {
      uri = Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': points.first,
      });
    } else {
      final origin = points.first;
      final destination = points.last;
      final waypoints = points.length > 2
          ? points.sublist(1, points.length - 1).take(20).join('|')
          : '';
      uri = Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'origin': origin,
        'destination': destination,
        if (waypoints.isNotEmpty) 'waypoints': waypoints,
      });
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Googleマップを開けませんでした')),
      );
    }
  }

  Widget _check(_MapLayer layer, String label, {required bool enabled}) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: enabled && _layers.contains(layer),
      onChanged: enabled
          ? (value) => setState(() {
                if (value == true) {
                  _layers.add(layer);
                } else {
                  _layers.remove(layer);
                }
              })
          : null,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('現場マップ'),
        actions: [
          const SkoNotificationBell(),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '同時に表示する項目',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            _check(
                              _MapLayer.sites,
                              '登録済みの現場全部',
                              enabled: data!.sites.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.customers,
                              '取引会社',
                              enabled: data.customers.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.partners,
                              '下請け会社',
                              enabled: data.partners.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.company,
                              '自社',
                              enabled: data.company != null,
                            ),
                            _check(
                              _MapLayer.home,
                              '自宅（本人）',
                              enabled: data.home != null,
                            ),
                            if (data.canViewAll && widget.allowEmployeeHomes)
                              _check(
                                _MapLayer.employeeHomes,
                                '全従業員の自宅',
                                enabled: data.employeeHomes.isNotEmpty,
                              ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _openSelectedTogether,
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('選択項目＋現在地をGoogleマップで表示'),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '現在地は位置情報が許可されている場合に自動で追加します。',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const _Heading('現場'),
                    for (final site in data.sites)
                      ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: Text(site['site_name']?.toString() ?? '現場'),
                        subtitle: Text(site['address']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(site, 'site_name'),
                      ),
                    const _Heading('取引会社'),
                    for (final customer in data.customers)
                      ListTile(
                        leading: const Icon(Icons.business_center_outlined),
                        title: Text(
                          customer['customer_name']?.toString() ?? '取引会社',
                        ),
                        subtitle: Text(customer['address']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(customer, 'customer_name'),
                      ),
                    if (data.partners.isNotEmpty) ...[
                      const _Heading('下請け会社'),
                      for (final partner in data.partners)
                        ListTile(
                          leading: const Icon(Icons.handshake_outlined),
                          title: Text(
                            partner['partner_name']?.toString() ?? '下請け会社',
                          ),
                          subtitle: Text(partner['address']?.toString() ?? ''),
                          trailing: const Icon(Icons.map_outlined),
                          onTap: () => _mapAddress(partner, 'partner_name'),
                        ),
                    ],
                    if (data.company != null) ...[
                      const _Heading('自社'),
                      ListTile(
                        leading: const Icon(Icons.apartment_outlined),
                        title: Text(
                          data.company!['company_name']?.toString() ?? '自社',
                        ),
                        subtitle: Text(data.company!['address']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(data.company!, 'company_name'),
                      ),
                    ],
                    if (data.home != null) ...[
                      const _Heading('自宅（本人）'),
                      ListTile(
                        leading: const Icon(Icons.home_outlined),
                        title: Text(
                          data.home!['worker_name']?.toString() ?? '自宅',
                        ),
                        subtitle: Text(data.home!['address']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(data.home!, 'worker_name'),
                      ),
                    ],
                    if (data.canViewAll &&
                        widget.allowEmployeeHomes &&
                        data.employeeHomes.isNotEmpty) ...[
                      const _Heading('全従業員の自宅'),
                      for (final worker in data.employeeHomes)
                        ListTile(
                          leading: const Icon(Icons.home_work_outlined),
                          title: Text(
                            worker['worker_name']?.toString() ?? '社員',
                          ),
                          subtitle: Text(worker['address']?.toString() ?? ''),
                          trailing: const Icon(Icons.map_outlined),
                          onTap: () => _mapAddress(worker, 'worker_name'),
                        ),
                    ],
                    const _Heading('最新の打刻位置'),
                    for (final worker in data.workers)
                      ListTile(
                        leading: const Icon(Icons.person_pin_circle_outlined),
                        title: Text(worker['worker_name']?.toString() ?? '社員'),
                        subtitle: Text(worker['site_name']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(
                          worker,
                          'worker_name',
                          preferAddress: false,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      );
}
