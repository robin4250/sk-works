/// Group-scoped, explicit aliases. Source messages are never rewritten.
enum LineReadingKind {
  site,
  worker,
  allowance,
  workCategory,
  overtime,
  early,
  ignore,
}

extension LineReadingKindLabel on LineReadingKind {
  String get label => switch (this) {
    LineReadingKind.site => '現場名',
    LineReadingKind.worker => '氏名',
    LineReadingKind.allowance => '手当',
    LineReadingKind.workCategory => '勤務区分',
    LineReadingKind.overtime => '残業',
    LineReadingKind.early => '早出',
    LineReadingKind.ignore => '読み取り対象外',
  };
}

class LineReadingRule {
  const LineReadingRule({
    required this.phrase,
    required this.kind,
    required this.value,
  });
  final String phrase, value;
  final LineReadingKind kind;
  Map<String, dynamic> toJson() => {
    'phrase': phrase,
    'kind': kind.name,
    'value': value,
  };
  factory LineReadingRule.fromJson(Map data) => LineReadingRule(
    phrase: data['phrase'] as String,
    kind: LineReadingKind.values.byName(data['kind'] as String),
    value: data['value'] as String,
  );
}

/// Split only on explicit separators; never guess Japanese word boundaries.
List<({String phrase, int count, String example})> lineReadingPhrases(
  List<Map<String, dynamic>> sources,
) {
  final counts = <String, int>{}, examples = <String, String>{};
  for (final source in sources) {
    final body = source['body']?.toString() ?? '';
    for (final token
        in body.split(RegExp(r'[\s　、,：:〈〉（）()]+')).map((v) => v.trim())) {
      final phrase = token.replaceFirst(
        RegExp(r'(?<=残業|早出)[0-9０-９]+(?:[.．][0-9０-９]+)?(?:時間|h)?$'),
        '',
      );
      if (phrase.isEmpty ||
          phrase.length > 80 ||
          RegExp(r'^[\d./年月日時分\-]+$').hasMatch(phrase))
        continue;
      counts[phrase] = (counts[phrase] ?? 0) + 1;
      examples.putIfAbsent(phrase, () => body);
    }
  }
  final result = [
    for (final e in counts.entries)
      (phrase: e.key, count: e.value, example: examples[e.key]!),
  ];
  result.sort((a, b) {
    final n = b.count.compareTo(a.count);
    return n == 0 ? a.phrase.compareTo(b.phrase) : n;
  });
  return result;
}

/// Automatic suggestions are deliberately limited to exact, unique references.
/// Explicit user rules take precedence. Unknown/ambiguous phrases stay unassigned.
LineReadingRule? lineAutomaticReadingRule(
  String phrase, {
  List<LineReadingRule> saved = const [],
  List<Map<String, dynamic>> sites = const [],
  List<Map<String, dynamic>> workers = const [],
  List<String> allowances = const [],
}) {
  final own = saved.where((r) => r.phrase == phrase).toList();
  if (own.length == 1) return own.single;
  if (own.length > 1) return null;
  final candidates = <LineReadingRule>[];
  for (final entry in [
    (LineReadingKind.site, sites),
    (LineReadingKind.worker, workers),
  ]) {
    final matches = entry.$2.where((v) => v['name'] == phrase).toList();
    if (matches.length == 1)
      candidates.add(
        LineReadingRule(phrase: phrase, kind: entry.$1, value: phrase),
      );
    if (matches.length > 1) return null;
  }
  if (allowances.where((a) => a == phrase).length == 1)
    candidates.add(
      LineReadingRule(
        phrase: phrase,
        kind: LineReadingKind.allowance,
        value: phrase,
      ),
    );
  if (phrase == '残業')
    candidates.add(
      LineReadingRule(
        phrase: phrase,
        kind: LineReadingKind.overtime,
        value: 'overtime_hours',
      ),
    );
  if (phrase == '早出')
    candidates.add(
      LineReadingRule(
        phrase: phrase,
        kind: LineReadingKind.early,
        value: 'early_hours',
      ),
    );
  if (candidates.length != 1) return null;
  return candidates.single;
}

/// Return review suggestions, not automatic edits. Confirmed/manual rows are locked.
List<Map<String, dynamic>> lineReadingSuggestions(
  List<Map<String, dynamic>> rows,
  List<LineReadingRule> rules,
) {
  final out = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (row['confirmed'] == true ||
        row['manually_edited'] == true ||
        row['edited'] == true)
      continue;
    for (final field in ['site_name', 'worker_name']) {
      final kind = field == 'site_name'
          ? LineReadingKind.site
          : LineReadingKind.worker;
      final matches = rules
          .where((r) => r.kind == kind && r.phrase == row[field])
          .toList();
      final values = matches.map((r) => r.value).toSet();
      if (values.length == 1 && values.single != row[field])
        out.add({
          'row_id': row['row_id'],
          'source_message_id': row['source_message_id'],
          'field': field,
          'before': row[field],
          'after': values.single,
          'requires_confirmation': true,
        });
    }
  }
  return out;
}
