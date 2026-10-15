import 'line_reading_rules.dart';

Map<String, dynamic> lineAssumedFields(Map<String, dynamic> row) {
  final value = row['assumed_fields'];
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

bool lineHasAssumedQuantities(Map<String, dynamic> row) =>
    lineAssumedFields(row).isNotEmpty;

/// Repair one field only; this never confirms the row or changes another estimate.
Map<String, dynamic> lineRepairAssumedQuantity(
    Map<String, dynamic> row, String field, double value) {
  if (!['overtime_hours', 'early_hours'].contains(field) ||
      !value.isFinite || value < 0 || value > 24) {
    throw ArgumentError('Invalid work hours');
  }
  final assumptions = lineAssumedFields(row)..remove(field);
  return {...row, field: value, 'assumed_fields': assumptions,
    'reading_origin': {'kind': 'manual'}};
}

String _digits(String value) {
  const full = '０１２３４５６７８９．';
  const ascii = '0123456789.';
  for (var i = 0; i < full.length; i++) {
    value = value.replaceAll(full[i], ascii[i]);
  }
  return value;
}

List<String> _tokens(String value) => _digits(value)
    .split(RegExp(r'[\s　、,，：:〈〉（）()]+'))
    .where((v) => v.isNotEmpty).toList();

/// Interpret tokens separately from the original source; never rewrite its body.
/// The caller applies this only to newly extracted, unconfirmed rows.
void lineApplyReadingFacts(Map<String, dynamic> row,
    List<Map<String, dynamic>> sources, List<Map<String, dynamic>> siblings,
    List<LineReadingRule> rules) {
  if (row['confirmed'] == true || row['manually_edited'] == true || row['edited'] == true) return;
  final source = sources.where((s) => s['id'] == row['source_message_id']).toList();
  if (source.length != 1 || source.single['body'] is! String) return;
  final worker = '${row['worker_name']}';
  final site = '${row['site_name']}';
  final workers = siblings.where((r) => r['source_message_id'] == row['source_message_id'] &&
    r['site_name'] == site).map((r) => '${r['worker_name']}').toSet();
  final siteLines = (source.single['body'] as String).split('\n')
      .map(_tokens).where((t) => t.isNotEmpty && t.first == _digits(site)).toList();
  final direct = siteLines.where((t) => t.skip(1).contains(_digits(worker))).toList();
  final status = siteLines.where((t) => !t.skip(1).any((v) => workers.any((w) => _digits(w) == v))).toList();
  // Never apply another worker's hours or choose between multiple site reports.
  final labels = {'残業', '早出', ...rules.where((r) =>
    r.kind != LineReadingKind.site && r.kind != LineReadingKind.worker).map((r) => _digits(r.phrase))};
  final directFacts = direct.where((t) => t.skip(1).any((v) =>
    labels.any((label) => v == label || RegExp('^${RegExp.escape(label)}[0-9]').hasMatch(v)))).toList();
  final lines = directFacts.isNotEmpty ? directFacts : status.length == 1 ? status : <List<String>>[];
  if (lines.isEmpty) return;
  final byPhrase = <String, LineReadingRule>{};
  final duplicate = <String>{};
  for (final rule in rules) {
    if (byPhrase.containsKey(rule.phrase)) duplicate.add(rule.phrase);
    byPhrase[rule.phrase] = rule;
  }
  for (final phrase in duplicate) { byPhrase.remove(phrase); }
  byPhrase.putIfAbsent('残業', () => const LineReadingRule(
    phrase: '残業', kind: LineReadingKind.overtime, value: 'overtime_hours'));
  byPhrase.putIfAbsent('早出', () => const LineReadingRule(
    phrase: '早出', kind: LineReadingKind.early, value: 'early_hours'));
  final facts = <String, List<double?>>{};
  final allowances = <String>{...?((row['allowance_names'] as List?)?.map((v) => '$v'))};
  final categories = <String>{};
  const categoryNames = {'day':'day','日勤':'day','night':'night','夜勤':'night',
    'holiday':'holiday','休日出勤':'holiday','holiday_night':'holiday_night','休日夜勤':'holiday_night'};
  for (final tokens in lines) {
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      for (final rule in byPhrase.values) {
        final phrase = _digits(rule.phrase);
        if (rule.kind == LineReadingKind.ignore) continue;
        if (rule.kind == LineReadingKind.overtime || rule.kind == LineReadingKind.early) {
          final match = RegExp('^${RegExp.escape(phrase)}([0-9]+(?:\\.[0-9]+)?)?(?:時間|[hH])?\$').firstMatch(token);
          if (match == null) continue;
          final field = rule.kind == LineReadingKind.overtime ? 'overtime_hours' : 'early_hours';
          final next = i + 1 < tokens.length ? RegExp(r'^([0-9]+(?:\.[0-9]+)?)(?:時間|[hH])?$').firstMatch(tokens[i + 1]) : null;
          final value = double.tryParse(match.group(1) ?? next?.group(1) ?? '');
          if (value == null || (value.isFinite && value >= 0 && value <= 24)) {
            facts.putIfAbsent(field, () => []).add(value);
          }
        } else if (token == phrase && rule.kind == LineReadingKind.allowance) {
          if (phrase == 'PC') { allowances.remove('PC'); allowances.remove('PC手当'); }
          if (phrase == '鉄骨') { allowances.remove('鉄骨'); allowances.remove('鉄骨手当'); }
          allowances.add(rule.value);
        } else if (token == phrase && rule.kind == LineReadingKind.workCategory) {
          final category = categoryNames[rule.value];
          if (category != null) categories.add(category);
        }
      }
    }
  }
  final assumptions = lineAssumedFields(row);
  for (final entry in facts.entries) {
    // Distinct reports for the same worker remain unconfirmed for manual repair.
    if (entry.value.length != 1) continue;
    final explicit = entry.value.single;
    row[entry.key] = explicit ?? 1.0;
    if (explicit == null) {
      assumptions[entry.key] = {'value':1.0,
        'reason':'勤務語はありますが時間の記載がないため1時間を仮置きしています。',
        'source_message_id':row['source_message_id']};
    } else {
      assumptions.remove(entry.key);
    }
  }
  if (assumptions.isNotEmpty) row['assumed_fields'] = assumptions;
  row['allowance_names'] = allowances.toList();
  if (categories.length == 1) {
    row['work_category'] = categories.single;
    row['night_work'] = categories.single == 'night' || categories.single == 'holiday_night';
  }
  // Ignoring a token changes only its interpretation; it never deletes a row.
  for (final rule in rules.where((r) => r.kind == LineReadingKind.ignore)) {
    final phrase = _digits(rule.phrase);
    final occurs = RegExp('^${RegExp.escape(phrase)}(?:[0-9]+(?:\\.[0-9]+)?)?(?:時間|[hH])?\$');
    if (!lines.any((t) => t.any((v) => occurs.hasMatch(v)))) continue;
    if (rule.phrase == '残業' && !facts.containsKey('overtime_hours')) {
      row['overtime_hours'] = 0.0; assumptions.remove('overtime_hours');
    }
    if (rule.phrase == '早出' && !facts.containsKey('early_hours')) {
      row['early_hours'] = 0.0; assumptions.remove('early_hours');
    }
    if (phrase == 'PC') { allowances.remove('PC'); allowances.remove('PC手当'); }
    if (phrase == '鉄骨') { allowances.remove('鉄骨'); allowances.remove('鉄骨手当'); }
  }
  row['allowance_names'] = allowances.toList();
  if (allowances.isEmpty && rules.any((r) => r.kind == LineReadingKind.ignore &&
      (r.phrase == 'PC' || r.phrase == '鉄骨'))) {
    row['steel_allowance'] = false;
  }
  if (row.containsKey('assumed_fields')) row['assumed_fields'] = assumptions;
}
