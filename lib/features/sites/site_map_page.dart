import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import 'site_map_repository.dart';

class SiteMapPage extends StatefulWidget {
  const SiteMapPage({super.key});

  @override
  State<SiteMapPage> createState() => _SiteMapPageState();
}

class _SiteMapPageState extends State<SiteMapPage> {
  final _repository = SiteMapRepository.maybeCreate();
  SiteMapWorkspace? _data;
  bool _loading = true;
  String? _error;

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

  Future<void> _map(Map<String, dynamic> row, String labelKey) async {
    final lat = row['latitude'] as num?;
    final lon = row['longitude'] as num?;
    final address = row['address']?.toString().trim() ?? '';
    final query = lat != null && lon != null
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
                        child: Text(
                          data!.canViewAll
                              ? '現場・取引会社・下請け会社と、社員全員の最新の打刻位置をGoogleマップで開けます。常時追跡は行いません。'
                              : '現場と自分自身の最新の打刻位置をGoogleマップで開けます。',
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
                        onTap: () => _map(site, 'site_name'),
                      ),
                    if (data.canViewAll) ...[
                      const _Heading('取引会社'),
                      for (final customer in data.customers)
                        ListTile(
                          leading: const Icon(Icons.business_center_outlined),
                          title: Text(
                            customer['customer_name']?.toString() ?? '取引会社',
                          ),
                          subtitle: Text(customer['address']?.toString() ?? ''),
                          trailing: const Icon(Icons.map_outlined),
                          onTap: () => _map(customer, 'customer_name'),
                        ),
                      const _Heading('下請け会社'),
                      for (final partner in data.partners)
                        ListTile(
                          leading: const Icon(Icons.handshake_outlined),
                          title: Text(
                            partner['partner_name']?.toString() ?? '下請け会社',
                          ),
                          subtitle: Text(partner['address']?.toString() ?? ''),
                          trailing: const Icon(Icons.map_outlined),
                          onTap: () => _map(partner, 'partner_name'),
                        ),
                    ],
                    const _Heading('社員の最新打刻位置'),
                    for (final worker in data.workers)
                      ListTile(
                        leading: const Icon(Icons.person_pin_circle_outlined),
                        title: Text(worker['worker_name']?.toString() ?? '社員'),
                        subtitle:
                            Text(worker['site_name']?.toString() ?? ''),
                        trailing: const Icon(Icons.map_outlined),
                        onTap: () => _map(worker, 'worker_name'),
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
