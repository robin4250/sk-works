import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/daily_reports/daily_report_zoom_pages.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_hit_target.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_pages.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_preview.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final signal = ValueNotifier<int>(0);
      var active = true;
      final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'synthetic-actor',
        companyId: 'synthetic-company', isCurrent: () => active, signal: signal,
        entries: dailyReportPhotoAttachments(photos, validateAccess: () async {
          if (!active) throw StateError('retired');
        }));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DailyReportPhotoPreview(photos: photos, gallery: gallery)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('daily-report-photo-thumbnail-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.textContaining('写真の本人 /'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.textContaining('先の失敗 /'), findsOneWidget);
      expect(find.text('添付を表示できませんでした。'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      await tester.tap(find.byKey(const ValueKey('daily-report-photo-thumbnail-1')));
      await tester.pumpAndSettle();
      active = false; signal.value++;
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing, reason: 'retired scope closes saved private bytes');
      await tester.pumpWidget(const SizedBox.shrink());
      signal.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('exact raster cover hit opens corresponding authorized photo and always closes', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final photos = [for (var i = 0; i < 12; i++) item('写真$i', 8 + i)];
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'actor', companyId: 'company',
      isCurrent: () => true, entries: dailyReportPhotoAttachments(photos, validateAccess: () async {}));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyReportZoomPages(
      pages: [PdfPreviewPageData(image: MemoryImage(photos.first.photoBytes!), width: 600, height: 800)],
      photoTargets: [const DailyReportPhotoHitTarget(pageIndex: 0, photoIndex: 7,
        bounds: Rect.fromLTWH(.2, .3, .15, .1))],
      photoHitBuilder: (_, index) => Opacity(opacity: 0, child: FittedBox(fit: BoxFit.fill,
        child: ResourceAttachmentThumbnail(key: ValueKey('cover-$index'),
          attachment: gallery.entries[index], gallery: gallery, requireGalleryScope: true))),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cover-7')));
    await tester.pumpAndSettle();
    expect(find.textContaining('写真7 /'), findsOneWidget);
    expect(find.text('8/12'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close)); await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
