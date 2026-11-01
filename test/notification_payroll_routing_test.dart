import 'package:sk_works/features/attendance/attendance_notification_page.dart';
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
import 'package:sk_works/features/sites/site_map_notification_page.dart';
import 'package:sk_works/features/sites/site_share_approval_page.dart';


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sk_works/features/approvals/approvals_hub_page.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:sk_works/features/invoices/invoice_notification_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/payroll/payroll_review_page.dart';
import 'package:sk_works/features/payroll/payroll_review_repository.dart';

const targetId = '12345678-1234-1234-1234-123456789abc';
AppNotificationRecord notice(String? action, {String? actionId = targetId}) => AppNotificationRecord(
  id: 'notice', kind: 'approval', title: '登録された氏名', body: '原文',
  createdAt: DateTime(2026, 10, 8), read: false,
  actionKey: action, actionId: actionId,
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

  test('saved attendance notice preserves the exact verification target', () {
    expect(notificationDestination(notice('attendance_today')), isA<AttendanceNotificationPage>().having((page) => page.verificationId, 'verification ID', targetId));
  });

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
    final route = notificationDestination(notice('invoice_approval')) as InvoiceNotificationPage;
    expect(route.invoiceId, targetId);
    expect(notificationDestination(notice('unknown_future_action')), isNull);
    expect(notificationDestination(notice(null)), isNull);
  });

  test('request notifications reject missing or malformed targets before routing', () {
    const actions = [
      'site_share_approval', 'paid_leave_request',
      'route_billing_quantity_request', 'daily_report_edit_request',
      'site_information_request', 'site_information_request_result',
      'attendance_correction_request', 'worker_personnel_change', 'invoice_approval',
    ];
    for (final action in actions) {
      for (final id in <String?>[null, '', ' ', 'not-a-uuid', '$targetId ', 'x$targetId']) {
        expect(notificationDestination(notice(action, actionId: id)), isNull,
          reason: '$action must not open another request list for $id');
      }
      expect(notificationDestination(notice(action)), isNotNull);
    }
  });

  test('target-free menu notices retain their existing destinations', () {
    for (final action in ['document_register', 'settings', 'admin_sites',
        'payment_certificate_settings', 'payroll_settings', 'site_payment_agreement']) {
      expect(notificationDestination(notice(action, actionId: null)), isNotNull,
        reason: '$action does not use actionId as a saved request target');
    }
  });

  test('missing map and invite target never opens a general list', () {
    expect(notificationDestination(notice('chat_group_invite', actionId: null)),
      isA<ChatCloudPage>().having((page) => page.initialInviteId, 'missing invite target', ''));
    expect(notificationDestination(notice('site_map', actionId: null)),
      isA<SiteMapNotificationPage>().having((page) => page.verificationId, 'missing map target', ''));
  });

  test('all known notification routes retain page types and request IDs', () {
    expect(notificationDestination(notice('chat_group_invite')),
      isA<ChatCloudPage>().having((page) => page.showGroupsInitially, 'group tab', true)
        .having((page) => page.initialInviteId, 'invitation ID', targetId));
    expect(notificationDestination(notice('site_map')), isA<SiteMapNotificationPage>().having((page) => page.verificationId, 'verification ID', targetId));
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
    final targetValidation = source.indexOf('notificationTargetIsValid(target.actionKey, target.actionId)');
    expect(targetValidation, greaterThanOrEqualTo(0));
    expect(readMutation, greaterThan(targetValidation));
    // _open owns the explanation lifetime; _openTarget owns resolution and its
    // outer failure handler. An inner package-preflight catch is not that handler.
    final opening = source.substring(source.indexOf('Future<void> _open('),
      source.indexOf('Future<void> _markBodyRead('));
    final targetOpening = source.substring(source.indexOf('Future<void> _openTarget('),
      source.indexOf('  @override\n  Widget build(BuildContext context)'));
    final failureStart = targetOpening.lastIndexOf('} catch (error) {');
    expect(failureStart, greaterThanOrEqualTo(0));
    final failureHandler = targetOpening.substring(failureStart);
    expect(failureHandler, matches(RegExp(
      r'^} catch \(error\) \{\s*_showError\(error\);\s*rethrow;\s*\}\s*\}\s*$')));
    expect(failureHandler, isNot(contains('markRead(')));
    final compact = opening.replaceAll(RegExp(r'\s+'), '');
    expect(compact, contains('if(_opening){return;}'));
    final cleanup = compact.indexOf('finally{flowClosed=true;');
    final cleanupComplete = compact.indexOf('awaitorderChanges?.close();');
    final reset = compact.indexOf('if(mounted){setState(()=>_opening=false);}');
    expect(cleanup, greaterThanOrEqualTo(0));
    expect(cleanupComplete, greaterThan(cleanup));
    expect(reset, greaterThan(cleanupComplete));
    expect(source, contains('onTap: _opening ? null : () => _open(item)'));
    expect(source, contains('Text(item.body)'));
    expect(source, contains('item.title,'));
  });
}
