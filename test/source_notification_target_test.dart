import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/source_notification_target.dart';

void main() {
  const company = '11111111-1111-1111-1111-111111111111';
  const source = '22222222-2222-2222-2222-222222222222';
  Map<String, Object> receipt(String key) => {'company_id': company,
    'source_id': source, 'event_key': key, 'work_date': '2026-09-30'};
  test('month-end target retains exact saved work date and ID', () {
    final target = SourceNotificationTarget.parse(receipt('group_report_saved'),
      expectedKey: 'group_report_saved', expectedSourceId: source);
    expect(target.databaseDate, '2026-09-30');
    target.validateRow({'id': source, 'company_id': company, 'report_date': '2026-09-30'});
    expect(() => target.validateRow({'id': source, 'company_id': company,
      'report_date': '2026-10-01'}), throwsFormatException);
  });
  test('wrong source, company, key and impossible dates cannot redirect', () {
    for (final patch in [ {'source_id': company}, {'company_id': 'bad'},
      {'event_key': 'payroll_review'}, {'work_date': '2026-02-30'} ]) {
      expect(() => SourceNotificationTarget.parse({...receipt('group_report_saved'), ...patch},
        expectedKey: 'group_report_saved', expectedSourceId: source), throwsFormatException);
    }
  });
  test('vehicle notification requires original clock-in rather than clock-out', () {
    final target = SourceNotificationTarget.parse(receipt('vehicle_driver_started'),
      expectedKey: 'vehicle_driver_started', expectedSourceId: source);
    expect(() => target.validateRow({'id': source, 'company_id': company,
      'work_date': '2026-09-30', 'event_type': 'clock_out'}), throwsFormatException);
  });
  test('report state is localized without treating viewing as approval', () {
    expect(sourceReportStatusLabel('draft', english: false), '下書き');
    expect(sourceReportStatusLabel('draft', english: true), 'Draft');
    expect(sourceReportStatusLabel('signed', english: false), '署名済み');
    expect(sourceReportStatusLabel('signed', english: true), 'Signed');
    expect(sourceReportStatusLabel('read', english: true), 'Status unavailable');
    expect(sourceReportStatusLabel(null, english: false), '状態を確認できません');
  });
  test('legacy keys never request source target RPC', () {
    expect(SourceNotificationTarget.supports('vehicle_documents'), isFalse);
    expect(SourceNotificationTarget.supports('daily_report_edit_request'), isFalse);
  });
}
