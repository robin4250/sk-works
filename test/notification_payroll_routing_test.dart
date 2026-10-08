import 'dart:io';

import 'package:sk_works/features/attendance/attendance_correction_approvals_page.dart';
import 'package:sk_works/features/attendance/paid_leave_approvals_page.dart';
import 'package:sk_works/features/chat/chat_cloud_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_approvals_page.dart';
import 'package:sk_works/features/operations/vehicle_route_page.dart';
import 'package:sk_works/features/payroll/individual_payroll_settings_page.dart';
import 'package:sk_works/features/payroll/payment_certificates_page.dart';
import 'package:sk_works/features/people/people_cloud_page.dart';
import 'package:sk_works/features/people/worker_personnel_change_approvals_page.dart';
import 'package:sk_works/features/settings/settings_page.dart';
import 'package:sk_works/features/sites/admin_site_financial_page.dart';
import 'package:sk_works/features/sites/site_information_approvals_page.dart';
import 'package:sk_works/features/sites/site_map_page.dart';
import 'package:sk_works/features/sites/site_share_approval_page.dart';


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sk_works/features/approvals/approvals_hub_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/payroll/payroll_review_page.dart';
import 'package:sk_works/features/payroll/payroll_review_repository.dart';

const targetId = '12345678-1234-1234-1234-123456789abc';
AppNotificationRecord notice(String? action) => AppNotificationRecord(
  id: 'notice', kind: 'approval', title: '登録された氏名', body: '原文',
  createdAt: DateTime(2026, 10, 8), read: false,
  actionKey: action, actionId: targetId,
);

void main() {
  tearDown(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));
  for (final item in <(Widget, String)>[
    (const NotificationsPage(), 'お知らせ'),
    (const ApprovalsHubPage(), '承認待ち'),
  ]) {
    testWidgets('${item.$2} changes language without replacing route state', (tester) async {
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
      await tester.pumpWidget(ValueListenableBuilder(
        valueListenable: SkoLanguageController.pack,
        builder: (context, pack, _) => MaterialApp(
          locale: Locale(pack.languageCode),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: item.$1,
        ),
      ));
      await tester.pumpAndSettle();
      final before = tester.state(find.byWidget(item.$1));
      expect(find.text(item.$2), findsOneWidget);
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      expect(tester.state(find.byWidget(item.$1)), same(before));
      expect(SkoLanguageController.tr(item.$2), isNot(item.$2));
      expect(find.text(SkoLanguageController.tr(item.$2)), findsOneWidget);
    });
  }

  test('payroll notice resolves its older month and retains secondary protection', () async {
    final month = await resolvePayrollNotificationMonth(targetId, (id) async {
      expect(id, targetId);
      return {'period_start': '2026-08-01'};
    });
    final route = notificationDestination(notice('payroll_review'), payrollMonth: month);
    expect(route, isA<SecondaryProtectedPage>());
    final review = (route as SecondaryProtectedPage).child as PayrollReviewPage;
    expect(review.initialMonth, DateTime(2026, 8));
  });

  test('inaccessible or invalid payroll targets do not default to current month', () async {
    await expectLater(resolvePayrollNotificationMonth(targetId, (_) async => null),
      throwsStateError);
    await expectLater(resolvePayrollNotificationMonth(targetId,
      (_) async => {'period_start': 'invalid'}), throwsStateError);
    var queried = false;
    await expectLater(resolvePayrollNotificationMonth('invalid', (_) async {
      queried = true; return null;
    }), throwsStateError);
    expect(queried, isFalse);
  });

  test('existing invoice target IDs and unsupported-action distinction remain', () {
    final route = notificationDestination(notice('invoice_approval')) as InvoiceCloudPage;
    expect(route.initialInvoiceId, targetId);
    expect(notificationDestination(notice('unknown_future_action')), isNull);
    expect(notificationDestination(notice(null)), isNull);
  });

  test('all known notification routes retain page types and request IDs', () {
    expect(notificationDestination(notice('chat_group_invite')),
      isA<ChatCloudPage>().having((page) => page.showGroupsInitially, 'group tab', true));
    expect(notificationDestination(notice('site_map')), isA<GeneralSiteMapPage>());
    expect(notificationDestination(notice('site_share_approval')), isA<SiteShareApprovalPage>()
      .having((page) => page.initialRequestId, 'target request', targetId));
    expect(notificationDestination(notice('vehicle_documents')), isA<VehicleRoutePage>());
    expect(notificationDestination(notice('paid_leave_request')), isA<PaidLeaveApprovalsPage>()
      .having((page) => page.initialRequestId, 'target request', targetId));
    expect(notificationDestination(notice('daily_report_edit_request')),
      isA<DailyReportApprovalsPage>()
        .having((page) => page.initialRequestId, 'target request', targetId));
    expect(notificationDestination(notice('worker_personnel_change_completed')), isA<PeopleCloudPage>());
    expect(notificationDestination(notice('settings')), isA<SettingsPage>());
    for (final key in ['site_information_request', 'site_information_request_result']) {
      expect(notificationDestination(notice(key)), isA<SiteInformationApprovalsPage>()
        .having((page) => page.initialRequestId, 'target request', targetId));
    }
    expect(notificationDestination(notice('attendance_correction_request')),
      isA<AttendanceCorrectionApprovalsPage>()
        .having((page) => page.initialRequestId, 'target request', targetId));
    expect(notificationDestination(notice('worker_personnel_change')),
      isA<WorkerPersonnelChangeApprovalsPage>()
        .having((page) => page.initialRequestId, 'target request', targetId));
  });

  test('financial settings routes keep their secondary protection', () {
    final cases = <String, Matcher>{
      'payroll_settings': isA<IndividualPayrollSettingsPage>(),
      'admin_sites': isA<AdminSiteFinancialPage>(),
      'payment_certificate_settings': isA<PartnerPaymentSettingsPage>(),
    };
    for (final entry in cases.entries) {
      final destination = notificationDestination(notice(entry.key));
      expect(destination, isA<SecondaryProtectedPage>());
      expect((destination as SecondaryProtectedPage).child, entry.value);
    }
  });

  test('period-only RLS query and resolution precede read mutation', () {
    final repository = File('lib/features/payroll/payroll_review_repository.dart').readAsStringSync();
    expect(repository.replaceAll(RegExp(r"\s+"), ""),
      contains(".select('period_start').eq('id',id).maybeSingle()"));
    final source = File('lib/features/notifications/notifications_page.dart').readAsStringSync();
    final resolution = source.indexOf('await review.notificationMonth');
    final readMutation = source.indexOf('await _notifications?.markRead(id)');
    expect(resolution, greaterThanOrEqualTo(0));
    expect(readMutation, greaterThan(resolution));
    final opening = source.substring(source.indexOf('Future<void> _open('),
      source.indexOf('Widget build(BuildContext context)'));
    final failureHandler = opening.substring(opening.indexOf('catch (error)'));
    expect(failureHandler, isNot(contains('markRead(')));
    final compact = opening.replaceAll(RegExp(r'\s+'), '');
    expect(compact, contains('if(_opening){return;}'));
    expect(compact, contains('finally{if(mounted){setState(()=>_opening=false);}}'));
    expect(source, contains('onTap: _opening ? null : () => _open(item)'));
    expect(source, contains('Text(item.body)'));
    expect(source, contains('item.title,'));
  });
}
