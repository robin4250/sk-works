import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/security/security_incident.dart';
import '../lib/features/security/security_incident_page.dart';

Map<String, dynamic> fixture() => {
  'version': 1,
  'incidents': [
    {
      'incident_id': '00000000-0000-4000-8000-000000000001',
      'correlation_id': '00000000-0000-4000-8000-000000000002',
      'detected_at': '2026-10-14T00:00:00Z',
      'window_from': '2026-10-13T23:59:00Z',
      'window_to': '2026-10-14T00:01:00Z',
      'status': 'detected',
      'collection_status': 'partial',
      'missing_before': true,
      'missing_after': false,
      'event_count': 1,
      'events': [
        {
          'sequence': 1,
          'at': '2026-10-14T00:00:00Z',
          'kind': 'current_lure_touched',
          'generation': 1,
        },
      ],
      'message_body': 'SECRET_BODY_NOT_ALLOWED',
      'ip': 'SECRET_IP_NOT_ALLOWED',
    },
  ],
};
void main() {
  test('report copies only allowlisted metadata and distinguishes detection from confirmation', () {
    final record = SecurityIncident.parseResponse(fixture()).single;
    final report = record.reportLines(false).join('\n');
    expect(report, contains('要調査'));
    expect(report, contains('一部不足'));
    expect(report, isNot(contains('SECRET')));
    expect(() => record.events.clear(), throwsUnsupportedError);
  });
  test('invalid metadata and collection mismatch fail closed', () {
    for (final key in [
      'incident_id',
      'status',
      'collection_status',
      'event_count',
      'window_to',
    ]) {
      final data = fixture();
      (data['incidents'] as List).single[key] = 'SECRET';
      expect(() => SecurityIncident.parseResponse(data), throwsFormatException);
    }
    expect(
      () => SecurityIncident.parseResponse({'incidents': []}),
      throwsFormatException,
    );
  });
  testWidgets('load failure is not displayed as an empty record list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityIncidentPage(
          loadRecords: () async => throw StateError('SECRET'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('記録を取得できません'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('保存された記録はありません。'), findsNothing);
  });
  testWidgets('record opens same sanitized report and export actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityIncidentPage(
          loadRecords: () async => SecurityIncident.parseResponse(fixture()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('要調査'));
    await tester.pumpAndSettle();
    expect(find.text('印刷'), findsOneWidget);
    expect(find.text('保存・共有'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
