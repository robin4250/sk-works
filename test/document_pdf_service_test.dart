import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_pdf_service.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';

void main() {
  test('attendance PDF snapshot contains monthly work rows', () {
    final month = DateTime(2026, 9);
    final data = WorkerAttendanceMonth(
      year: 2026,
      month: 9,
      days: {
        DateTime(2026, 9, 1): WorkerAttendanceDay(
          date: DateTime(2026, 9, 1),
          siteName: '新宿現場',
          clockIn: DateTime(2026, 9, 1, 8),
          clockOut: DateTime(2026, 9, 1, 17),
          overtimeHours: 1,
        ),
      },
    );
    final text = AttendancePdfService.buildTextSnapshot(month, data);
    expect(text, contains('出勤表 2026年9月'));
    expect(text, contains('新宿現場'));
    expect(text, contains('08:00-17:00'));
  });

  test('daily report PDF snapshot includes workers and signer', () {
    final date = DateTime(2026, 9, 21);
    final workers = [
      DailyReportWorkerDraft(workerId: 'w1', workerName: '山田太郎'),
    ];
    final report = DailyReportRecord(
      id: 'r1',
      siteId: 's1',
      siteName: '品川現場',
      date: date,
      workDescription: '配管工事',
      status: 'signed',
      workers: workers,
      signerName: '現場責任者',
    );
    final text = DailyReportPdfService.buildTextSnapshot(
      date: date,
      siteName: '品川現場',
      workers: workers,
      workDescription: '配管工事',
      report: report,
    );
    expect(text, contains('作業日報'));
    expect(text, contains('山田太郎'));
    expect(text, contains('現場責任者'));
  });

  test('payroll PDF snapshot includes protected payroll totals', () {
    final statement = PayrollStatementRecord(
      id: 'p1',
      companyName: 'SK WORKS',
      workerName: '山田太郎',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 30),
      grossPay: 350000,
      deductions: 50000,
      netPay: 300000,
      detail: const {'基本給': 300000},
    );
    final text = PayrollPdfService.buildTextSnapshot(statement);
    expect(text, contains('給与明細'));
    expect(text, contains('SK WORKS'));
    expect(text, contains('¥300,000'));
  });
}
