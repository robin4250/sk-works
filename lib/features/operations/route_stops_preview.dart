import 'package:flutter/material.dart';

class RouteStopsPreview extends StatelessWidget {
  const RouteStopsPreview({super.key, required this.route});
  final Map<String, dynamic>? route;

  @override
  Widget build(BuildContext context) {
    if (route == null) return const SizedBox.shrink();
    final raw = route!['route_stops'];
    final stops = raw is List ? raw.whereType<Map>().toList() : <Map>[];
    stops.sort(
      (a, b) => ((a['stop_order'] as num?)?.toInt() ?? 0).compareTo(
        (b['stop_order'] as num?)?.toInt() ?? 0,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          '回る順番（${stops.length}地点）',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text('登録済みルートの予定順です。'),
        if (stops.isEmpty) const Text('地点が未登録です。ルート管理で登録してください。'),
        for (var i = 0; i < stops.length; i++)
          _stopPreview(context, stops[i], i + 1),
      ],
    );
  }

  Widget _stopPreview(BuildContext context, Map stop, int number) {
    final site = stop['sites'];
    final siteName = site is Map ? site['name']?.toString().trim() ?? '' : '';
    final label = stop['source_label']?.toString().trim() ?? '';
    final savedAddress = stop['address']?.toString().trim() ?? '';
    final address = savedAddress.isNotEmpty
        ? savedAddress
        : site is Map
        ? site['address']?.toString().trim() ?? ''
        : '';
    final title = label.isNotEmpty
        ? label
        : siteName.isNotEmpty
        ? siteName
        : address.isNotEmpty
        ? address
        : '地点名未登録';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text('$number.')),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                if (address.isNotEmpty && address != title)
                  Text(address, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
