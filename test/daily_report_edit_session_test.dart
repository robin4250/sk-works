import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_edit_session.dart';

void main() {
  test('exact actor/company/report/request survives pending then confirmed without signature data', () async {
    final data = <String, String>{};
    final store = DailyReportEditSessionStore(read: (key) async => data[key],
      write: (key, value) async { data[key] = value; },
      remove: (key) async { data.remove(key); });
    const session = DailyReportEditSession(actorId: 'a', companyId: 'c',
      reportId: 'r', requestId: 'q');
    await store.remember(session);
    expect((await store.load('a', 'r'))!.confirmed, isFalse);
    expect(await store.load('other', 'r'), isNull);
    await store.remember(session.confirm());
    final restored = (await store.load('a', 'r'))!;
    expect(restored.requestId, 'q');
    expect(restored.companyId, 'c');
    expect(restored.confirmed, isTrue);
    expect(jsonDecode(data.values.single).keys, unorderedEquals(
      ['actor', 'company', 'report', 'request', 'confirmed']));
    await store.clear(restored);
    expect(await store.load('a', 'r'), isNull);
  });
  test('mismatched actor or report in persisted value is rejected', () async {
    final store = DailyReportEditSessionStore(read: (_) async => jsonEncode(
      const DailyReportEditSession(actorId: 'other', companyId: 'c',
        reportId: 'r', requestId: 'q').toJson()),
      write: (_, _) async {}, remove: (_) async {});
    await expectLater(store.load('a', 'r'), throwsFormatException);
  });
}
