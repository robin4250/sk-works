import 'dart:convert';
import 'dart:math';

/// Fixed command identity and raw evidence; server work_date is never provided.
class RouteJourneyCaptureDraft {
  RouteJourneyCaptureDraft({required this.userId, required this.companyId,
    required this.sourceId, required this.stopId, required this.originKind,
    required Map<String, Object?> payload, DateTime? preparedAt})
    : id = _uuid(), preparedAt = (preparedAt ?? DateTime.now()).toUtc(),
      payload = _freeze(payload) as Map<String, Object?>;
  RouteJourneyCaptureDraft._({required this.id, required this.userId,
    required this.companyId, required this.sourceId, required this.stopId,
    required this.originKind, required this.preparedAt, required this.payload});
  factory RouteJourneyCaptureDraft.restore(String encoded) {
    final data = jsonDecode(encoded) as Map;
    final payload = Map<String, Object?>.from(data['payload'] as Map);
    final prepared = DateTime.tryParse(data['prepared_at']?.toString() ?? '');
    if (data['version'] != 1 || prepared == null ||
        ['id', 'user_id', 'company_id', 'source_id', 'stop_id'].any((key) => data[key] is! String || (data[key] as String).isEmpty) ||
        !['company', 'direct'].contains(data['origin_kind']) ||
        payload['capture_contract_version'] != 1 || payload.containsKey('work_date') ||
        payload.containsKey('confirmed_at')) {
      throw StateError('保留中の途中現場記録を確認できません');
    }
    return RouteJourneyCaptureDraft._(id: data['id'], userId: data['user_id'],
      companyId: data['company_id'], sourceId: data['source_id'], stopId: data['stop_id'],
      originKind: data['origin_kind'], preparedAt: prepared.toUtc(), payload: _freeze(payload) as Map<String, Object?>);
  }
  final String id, userId, companyId, sourceId, stopId, originKind;
  final DateTime preparedAt;
  final Map<String, Object?> payload;
  String get encoded => jsonEncode({'version': 1, 'id': id, 'user_id': userId,
    'company_id': companyId, 'source_id': sourceId, 'stop_id': stopId,
    'origin_kind': originKind, 'prepared_at': preparedAt.toIso8601String(), 'payload': payload});
  bool canInsertOn(DateTime now) {
    String day(DateTime value) => value.toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0, 10);
    return day(preparedAt) == day(now);
  }
  bool matchesRow(Map<String, dynamic> row) {
    final raw = row['payload'];
    return row['id'] == id && row['company_id'] == companyId && row['created_by'] == userId &&
      row['source_clock_in_id'] == sourceId && row['route_stop_id'] == stopId &&
      row['origin_kind'] == originKind && row['work_date'] is String &&
      row['recorded_at'] is String && raw is Map && raw.length == payload.length &&
      payload.entries.every((entry) => _sameJson(raw[entry.key], entry.value));
  }
  static Object? _freeze(Object? value) {
    if (value is Map) return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key.toString(): _freeze(entry.value)});
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }
  static bool _sameJson(Object? a, Object? b) {
    if (a is Map && b is Map) return a.length == b.length &&
      a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
    if (a is List && b is List) return a.length == b.length &&
      List.generate(a.length, (index) => index).every((index) => _sameJson(a[index], b[index]));
    return a == b;
  }
  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }
}

Future<Map<String, dynamic>> recoverRouteJourneyCapture(RouteJourneyCaptureDraft draft, {
  required Future<Map<String, dynamic>?> Function() readExact,
  required Future<Map<String, dynamic>> Function() insert,
}) async {
  Map<String, dynamic> check(Map<String, dynamic> row) {
    if (!draft.matchesRow(row)) throw StateError('保留中の途中現場記録が一致しません');
    return row;
  }
  final existing = await readExact(); // Failure MUST NOT fall through to insert.
  if (existing != null) return check(existing);
  try { return check(await insert()); }
  catch (_) {
    final recovered = await readExact();
    if (recovered == null) rethrow;
    return check(recovered);
  }
}
