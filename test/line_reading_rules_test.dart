import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/chat/line_reading_rules.dart';

void main() {
  test('unique references suggest category; ambiguity and manual choices are preserved', () {
    expect(
      lineAutomaticReadingRule(
        '新宿',
        sites: [
          {'name': '新宿'},
        ],
      )?.kind,
      LineReadingKind.site,
    );
    expect(
      lineAutomaticReadingRule(
        '新宿',
        sites: [
          {'name': '新宿'},
        ],
        workers: [
          {'name': '新宿'},
        ],
      ),
      isNull,
    );
    expect(lineAutomaticReadingRule('残業')?.kind, LineReadingKind.overtime);
    expect(
      lineAutomaticReadingRule(
        '残業',
        saved: [
          const LineReadingRule(
            phrase: '残業',
            kind: LineReadingKind.allowance,
            value: '特殊手当',
          ),
        ],
      )?.kind,
      LineReadingKind.allowance,
    );
    expect(
      lineReadingPhrases([
        {'body': '残業1 残業2 早出1'},
      ]).first.count,
      2,
    );
  });
  test('frequency preserves examples and source bodies', () {
    final sources = [
      {'id': '1', 'body': '愛宕 三嶋 PC'},
      {'id': '2', 'body': '愛宕 三上 PC'},
    ];
    final phrases = lineReadingPhrases(sources);
    expect(phrases.firstWhere((p) => p.phrase == '愛宕').count, 2);
    expect(sources.first['body'], '愛宕 三嶋 PC');
  });
  test('exact aliases propose review and preserve source identity', () {
    final rows = [
      {'row_id': 'r', 'source_message_id': 's', 'site_name': '愛宕'},
    ];
    final rules = [
      const LineReadingRule(
        phrase: '愛宕',
        kind: LineReadingKind.site,
        value: '愛宕ビル工事',
      ),
    ];
    final result = lineReadingSuggestions(rows, rules);
    expect(result.single['after'], '愛宕ビル工事');
    expect(result.single['source_message_id'], 's');
    expect(rows.single['site_name'], '愛宕');
    expect(result.single['requires_confirmation'], true);
  });
  test('confirmed manual and ambiguous rows cannot be overwritten', () {
    final rule = const LineReadingRule(
      phrase: '愛宕',
      kind: LineReadingKind.site,
      value: '正式名',
    );
    expect(
      lineReadingSuggestions(
        [
          {'site_name': '愛宕', 'confirmed': true},
          {'site_name': '愛宕', 'manually_edited': true},
        ],
        [rule],
      ),
      isEmpty,
    );
    expect(
      lineReadingSuggestions(
        [
          {'site_name': '愛宕'},
        ],
        [
          rule,
          const LineReadingRule(
            phrase: '愛宕',
            kind: LineReadingKind.site,
            value: '別の現場',
          ),
        ],
      ),
      isEmpty,
    );
  });
}
