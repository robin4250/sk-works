import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_week_date_label.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_page.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';

void main() {
  testWidgets('full long holiday name fits a compact weekly row at large text size', (tester) async {
    for (final name in ['建国記念の日', '勤労感謝の日', 'スポーツの日']) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Center(child: SizedBox(height: 34, child: AttendanceWeekDateLabel(date: DateTime(2026, 11, 23), weekday: '月', holidayName: name))),
        )),
      ));
      await tester.pump();
      final text = tester.widget<Text>(find.text(name));
      expect(text.style!.fontSize, 12);
      expect(text.overflow, isNull);
      final painter = TextPainter(text: TextSpan(text: name, style: text.style), textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(1.3), maxLines: text.maxLines)..layout(maxWidth: 110);
      expect(painter.didExceedMaxLines, isFalse);
      expect(painter.height, lessThan(34));
      painter.dispose();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('calendar hides holiday names and header preview opens with current month data', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SkoScrollChromeController.visible.value = false;
    addTearDown(() => SkoScrollChromeController.visible.value = true);
    final date = DateTime(2026, 11, 23);
    final data = WorkerAttendanceMonth(year: 2026, month: 11, days: {
      date: WorkerAttendanceDay(date: date, siteName: '登録現場', clockIn: DateTime(2026, 11, 23, 8), clockOut: DateTime(2026, 11, 23, 17), manDays: 1),
    });
    await tester.pumpWidget(MaterialApp(home: WorkerAttendanceMonthPage(month: date, data: data, workerName: '社員A')));
    await tester.pumpAndSettle();
    expect(find.text('勤労感謝の日'), findsNothing);
    final headerButton = find.byTooltip('A4印刷プレビュー');
    expect(headerButton.hitTestable(), findsOneWidget);
    await tester.tap(headerButton);
    await tester.pumpAndSettle();
    final preview = tester.widget<WorkerAttendancePrintPreviewPage>(find.byType(WorkerAttendancePrintPreviewPage));
    expect(preview.data, same(data));
    expect(preview.month, DateTime(2026, 11));
    expect(find.text('A4プレビュー'), findsOneWidget);
    expect(find.textContaining('登録現場'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(SkoScrollChromeController.visible.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
