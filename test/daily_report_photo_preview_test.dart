import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_pages.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_preview.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

void main() {
  DailyReportPdfEvidence item(
    String id,
    int hour, {
    bool manual = false,
    bool failed = false,
  }) => DailyReportPdfEvidence(
    record: DailyReportEvidenceRecord(
      id: id,
      workerName: id,
      eventType: 'clock_in',
      confirmedAt: DateTime(2026, 10, 11, hour),
      storagePath: failed || manual ? '' : '$id.png',
      timeOnly: manual,
      photoStatus: failed ? 'failed' : null,
      capturedAddress: '東京都墨田区横川1-9',
      stopLabel: '実際現場',
    ),
    photoBytes: failed || manual
        ? null
        : base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAACA0lEQVR4nO3bPU4DMRAF4BfCMThKJMqUuQUFh0iRQ1DkFpQpkXIK6jRcAQmJYqXVar3rN7bHY4jnVcD+ePJl7F2xyebz6xue9Ty0LuCvx4FIHIjEgUgciMSBSByIxIFIHIjkMb75+eXNpo6G+Ti/RrZ6B5E4EAmZYmPiffgfI1w9vINIHIikU6DdaS/cs0egQefn6V2yc3dA096RGPUFNJtZ29uBHtIRUIYO+gGa6VyPF+GBXQBl66AHoBId3D1QoQ7uG6hcB5ZAQ7nyW1iV4cbk6cAMaKpjYKSlAxugUGR32tdjUtSBAVAEwqCVCnVQFUjSJupG0xOW66Ae0OIrvx4vYdGK001dB5WA1nRmP9BDygctj/R/0vKEhYYiw19mew6/5r3zugvzNModJNGJb8pohHo60AVK0onskGRUVQeKQBk6427ZK3dtHagALb6Y1FozWslAB+VA8QtWUpKMbHRQCKSoMx4rmW5mOigBWpxWKrXGW8lSB9n3QeWLTjyRG6V6gy4mp4PMCo2f1kAHGUDGb+PayW10kDTF1JdkYcLpZqYDeQe10pmNpXUdkEcEtPgM27jQJiNCMsVCnSaFtgrvoNkz7K50kHoV600HQqChiTrUgfwyv70devhQeZh7fvSsEgci2fi3nuPxDiJxIBIHInEgEgcicSASByJxIBIHIvkFUQHikY9nhEsAAAAASUVORK5CYII=',
          ),
  );

  test('photograph pages retain failures, exclude manual events and order by actual record time', () {
    final photos = dailyReportPhotoRecords([
      item('後の本人', 11),
      item('手動本人', 10, manual: true),
      item('先の失敗', 9, failed: true),
    ]);
    expect(photos.map((p) => p.record.id), ['先の失敗', '後の本人']);
    expect(dailyReportPhotoLocation(photos[0]), '東京都墨田区横川1-9');
    expect(dailyReportPhotoTime(photos[0]), '2026/10/11 09:00');
    expect(dailyReportPhotoRecords([item('manual', 9, manual: true)]), isEmpty);
  });

  testWidgets(
    'small thumbnail opens its saved photo and swipes to other evidence including failure',
    (tester) async {
      final photos = dailyReportPhotoRecords([
        item('先の失敗', 9, failed: true),
        item('写真の本人', 10),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DailyReportPhotoPreview(photos: photos)),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('daily-report-photo-thumbnail')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('2/2 写真の本人'), findsOneWidget);
      expect(find.textContaining('2026/10/11 10:00'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(find.text('1/2 先の失敗'), findsOneWidget);
      expect(find.text('写真未登録・送信失敗'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
