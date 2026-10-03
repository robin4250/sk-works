import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import '../../international/language_controller.dart';
import 'site_map_repository.dart';

enum _MapLayer { sites, customers, partners, company, home, employeeHomes }

enum SiteMapMode { general, admin }

class GeneralSiteMapPage extends StatelessWidget {
  const GeneralSiteMapPage({super.key});

  @override
  Widget build(BuildContext context) => const SiteMapPage(
        mode: SiteMapMode.general,
        title: '現場マップ',
      );
}

class AdminSiteMapPage extends StatelessWidget {
  const AdminSiteMapPage({super.key});

  @override
  Widget build(BuildContext context) => const SiteMapPage(
        mode: SiteMapMode.admin,
        title: '管理者用現場マップ',
      );
}

class SiteMapPage extends StatefulWidget {
  const SiteMapPage({
    super.key,
    required this.mode,
    required this.title,
  });

  final SiteMapMode mode;
  final String title;

  bool get allowEmployeeHomes => mode == SiteMapMode.admin;

  @override
  State<SiteMapPage> createState() => _SiteMapPageState();
}

class _SiteMapPageState extends State<SiteMapPage> {
  final _repository = SiteMapRepository.maybeCreate();
  SiteMapWorkspace? _data;
  bool _loading = true;
  String? _error;
  late final Set<_MapLayer> _layers;

  @override
  void initState() {
    super.initState();
    _layers = widget.mode == SiteMapMode.admin
        ? <_MapLayer>{
            _MapLayer.sites,
            _MapLayer.customers,
            _MapLayer.partners,
            _MapLayer.company,
            _MapLayer.home,
          }
        : <_MapLayer>{
            _MapLayer.sites,
            _MapLayer.customers,
            _MapLayer.company,
            _MapLayer.home,
          };
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = _repository;
      if (repository == null) throw StateError(SkoLanguageController.tr('現場マップを利用できません'));
      final value = await repository.load();
      if (!mounted) return;
      setState(() {
        _data = value;
        if (!value.canViewAll || !widget.allowEmployeeHomes) {
          _layers.remove(_MapLayer.employeeHomes);
        }
        // The footer map must still show the signed-in user's own home.
        // Only other employees' homes are restricted by allowEmployeeHomes.
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
        SnackBar(content: Text(SkoLanguageController.tr('Googleマップで開ける位置情報がありません'))),
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

    final points = <Map<String, dynamic>>[
      if (current != null)
        {
          'name': SkoLanguageController.tr('現在地'),
          'address': '',
          'latitude': current.latitude,
          'longitude': current.longitude,
        },
      for (final row in selected)
        {
          'name': _placeName(row),
          'address': row['address']?.toString().trim() ?? '',
          if (row['latitude'] is num)
            'latitude': (row['latitude'] as num).toDouble(),
          if (row['longitude'] is num)
            'longitude': (row['longitude'] as num).toDouble(),
        },
    ].where((row) {
      final address = row['address']?.toString().trim() ?? '';
      return address.isNotEmpty ||
          (row['latitude'] is num && row['longitude'] is num);
    }).toList(growable: false);

    if (points.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('表示する地点を選択してください'))),
      );
      return;
    }

    if (Platform.isIOS) {
      try {
        await const MethodChannel('sko.multi_pin_map').invokeMethod<void>(
          'show',
          {
            'title': SkoLanguageController.tr('現場マップ'),
            'points': points,
          },
        );
        return;
      } on MissingPluginException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SkoLanguageController.tr('iPhone地図機能を読み込めませんでした。アプリを更新してください。'))),
        );
        return;
      } on PlatformException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${SkoLanguageController.tr('複数ピン地図を開けませんでした')}: ${error.message ?? ''}')),
        );
        return;
      }
    }

    // iOS以外では単一地点をGoogleマップで開く。ルート表示にはしない。
    final first = points.first;
    final query = (first['address']?.toString().trim().isNotEmpty ?? false)
        ? first['address'].toString()
        : '${first['latitude']},${first['longitude']}';
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('地図を開けませんでした'))),
      );
    }
  }

  String _placeName(Map<String, dynamic> row) {
    for (final key in const [
      'site_name',
      'customer_name',
      'partner_name',
      'company_name',
      'worker_name',
    ]) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return SkoLanguageController.tr('地点');
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
        title: Text(SkoLanguageController.tr(widget.title)),
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
                            Text(
                              SkoLanguageController.tr('同時に表示する項目'),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            _check(
                              _MapLayer.sites,
                              SkoLanguageController.tr('登録済みの現場全部'),
                              enabled: data!.sites.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.customers,
                              SkoLanguageController.tr('取引会社'),
                              enabled: data.customers.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.partners,
                              SkoLanguageController.tr('下請け会社'),
                              enabled: data.partners.isNotEmpty,
                            ),
                            _check(
                              _MapLayer.company,
                              SkoLanguageController.tr('自社'),
                              enabled: data.company != null,
                            ),
                            if (widget.allowEmployeeHomes)
                              _check(
                                _MapLayer.home,
                                SkoLanguageController.tr('自宅（本人）'),
                                enabled: data.home != null,
                              ),
                            if (data.canViewAll && widget.allowEmployeeHomes)
                              _check(
                                _MapLayer.employeeHomes,
                                SkoLanguageController.tr('全従業員の自宅'),
                                enabled: data.employeeHomes.isNotEmpty,
                              ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _openSelectedTogether,
                              icon: const Icon(Icons.map_outlined),
                              label: Text(SkoLanguageController.tr('選択地点を複数ピンで地図表示')),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'ルート表示ではなく、選択した地点を📍で同時表示します。iPhoneでは標準MapKitを使用します。',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    _Heading(SkoLanguageController.tr('現場')),
                    for (final site in data.sites)
                      ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: Text(site['site_name']?.toString() ?? '現場'),
                        subtitle: Text(site['address']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _mapAddress(site, 'site_name'),
                      ),
                    _Heading(SkoLanguageController.tr('取引会社')),
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
                      _Heading(SkoLanguageController.tr('下請け会社')),
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
                      _Heading(SkoLanguageController.tr('自社')),
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
                      _Heading(SkoLanguageController.tr('自宅（本人）')),
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
                      _Heading(SkoLanguageController.tr('全従業員の自宅')),
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
                    _Heading(SkoLanguageController.tr('最新の打刻位置')),
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
