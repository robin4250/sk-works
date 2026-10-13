import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TrafficShortcutScope {
  const TrafficShortcutScope({required this.actorId, required this.companyId});
  final String actorId;
  final String companyId;
  bool get valid => actorId.trim().isNotEmpty && companyId.trim().isNotEmpty;
  String get storageKey => 'traffic_shortcut_v1_${base64Url.encode(utf8.encode(jsonEncode([actorId, companyId])))}';
  @override
  bool operator ==(Object other) => other is TrafficShortcutScope && actorId == other.actorId && companyId == other.companyId;
  @override
  int get hashCode => Object.hash(actorId, companyId);
}

enum TrafficShortcutKind { googleMaps, web }

class TrafficShortcut {
  const TrafficShortcut.googleMaps() : kind = TrafficShortcutKind.googleMaps, label = 'Googleマップ', webUrl = null;
  const TrafficShortcut._web(this.label, this.webUrl) : kind = TrafficShortcutKind.web;
  final TrafficShortcutKind kind;
  final String label;
  final Uri? webUrl;
  Uri get uri => kind == TrafficShortcutKind.googleMaps ? Uri.parse('comgooglemaps://') : webUrl!;
  static TrafficShortcut? web(String name, String url) {
    final label = name.trim();
    final uri = Uri.tryParse(url.trim());
    if (label.isEmpty || label.length > 30 || uri == null || uri.scheme != 'https' ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || RegExp(r'[\s\x00-\x1f]').hasMatch(url.trim())) {
      return null;
    }
    return TrafficShortcut._web(label, uri);
  }
  Map<String, dynamic> toJson() => {'version': 1, 'kind': kind.name, 'label': label, if (webUrl != null) 'url': webUrl.toString()};
  static TrafficShortcut? fromJson(Object? value) {
    if (value is! Map || value['version'] != 1) return null;
    if (value['kind'] == 'googleMaps') return const TrafficShortcut.googleMaps();
    if (value['kind'] == 'web' && value['label'] is String && value['url'] is String) {
      return web(value['label'] as String, value['url'] as String);
    }
    return null;
  }
}

abstract class TrafficShortcutStore {
  Future<TrafficShortcut?> load(TrafficShortcutScope scope);
  Future<void> save(TrafficShortcutScope scope, TrafficShortcut? shortcut);
}

class DeviceTrafficShortcutStore implements TrafficShortcutStore {
  @override
  Future<TrafficShortcut?> load(TrafficShortcutScope scope) async {
    if (!scope.valid) return null;
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(scope.storageKey);
    if (raw == null) return null;
    try { return TrafficShortcut.fromJson(jsonDecode(raw)); } catch (_) { return null; }
  }
  @override
  Future<void> save(TrafficShortcutScope scope, TrafficShortcut? shortcut) async {
    if (!scope.valid) throw StateError('Shortcut account unavailable');
    final preferences = await SharedPreferences.getInstance();
    final success = shortcut == null
        ? await preferences.remove(scope.storageKey)
        : await preferences.setString(scope.storageKey, jsonEncode(shortcut.toJson()));
    if (!success) throw StateError('Shortcut save failed');
  }
}
