class LineHistoricalGroup {
  LineHistoricalGroup(this.siteId, this.category, this.siteName);
  final String siteId, category, siteName;
  final Set<String> workers = {};
  final Map<String, int> allowances = {};
  double manDays = 0, overtime = 0, early = 0;
}

List<LineHistoricalGroup> historicalGroups(List<Map<String, dynamic>> rows) {
  final groups = <String, LineHistoricalGroup>{};
  for (final row in rows.where((r) => r['excluded'] != true)) {
    if (row['confirmed'] != true || row['worker_id'] is! String ||
        row['site_id'] is! String || row['work_category'] is! String ||
        row['allowance_names'] is! List ||
        !['day', 'night', 'holiday', 'holiday_night'].contains(row['work_category']) ||
        (row['worker_id'] as String).trim().isEmpty || (row['site_id'] as String).trim().isEmpty) {
      throw StateError('確認済みの人数・数量・手当を確認してください。');
    }
    double quantity(String key) {
      final value = row[key];
      final n = value is num ? value.toDouble() : double.tryParse('$value');
      if (n == null || !n.isFinite || n < 0) throw StateError('数量が未取得です。');
      return n;
    }
    if (![0.5, 1.0].contains(quantity('man_days')) || quantity('overtime_hours') > 24 || quantity('early_hours') > 24) throw StateError('確認済み数量の範囲を確認してください。');
    final key = '${row['site_id']}:${row['work_category']}';
    final group = groups.putIfAbsent(key, () => LineHistoricalGroup(
      row['site_id'] as String, row['work_category'] as String,
      row['site_name']?.toString() ?? '現場'));
    group.workers.add(row['worker_id'] as String);
    group.manDays += quantity('man_days');
    group.overtime += quantity('overtime_hours');
    group.early += quantity('early_hours');
    for (final name in (row['allowance_names'] as List).toSet()) {
      if (name is! String || name.trim().isEmpty) throw StateError('手当名が未取得です。');
      group.allowances[name] = (group.allowances[name] ?? 0) + 1;
    }
  }
  return groups.values.toList();
}

int? historicalUnitRate(String input) {
  if (!RegExp(r'^\d+$').hasMatch(input.trim())) return null;
  final rate = int.tryParse(input.trim());
  return rate != null && rate <= 100000000 ? rate : null;
}
