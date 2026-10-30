import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/payroll/payroll_confirmation_repository.dart';
import 'package:sk_works/features/payroll/payroll_pending_attendance_panel.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/payroll/payroll_statements_page.dart';
import 'package:sk_works/features/qualifications/own_qualification_registration_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

import 'fixtures/payroll_insurance_evidence_fixture.dart';

class _Qualifications implements QualificationCloudRepository {
  @override
  String get currentUserId => 'synthetic-actor';
  @override
  Future<Map<String, dynamic>> loadOwnQualificationWorkspace() async => {
    'worker': {'id': 'synthetic-worker', 'name': '確認用の作業員'},
    'masters': [
      {'id': 'synthetic-master', 'name': '取得済み資格', 'category': '国家資格'},
    ],
    'qualifications': [
      {'id': 'synthetic-qualification', 'worker_id': 'synthetic-worker',
       'qualification_master_id': 'synthetic-master', 'issued_at': '2024-04-01',
       'attachment_path': null, 'attachment_back_path': null},
    ],
  };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pending implements AttendanceManagementRepository {
  @override
  Stream<AuthState> get authChanges => const Stream.empty();
  @override
  Future<PayrollPendingAttendance?> loadPayrollPendingDays(String id) async =>
      PayrollPendingAttendance(workerId: 'synthetic-worker', dates: [DateTime(2026, 10, 13)]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('qualification list owns most of a phone screen while scope and photo policy remain in help', (tester) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(home: OwnQualificationRegistrationPage(repository: _Qualifications())));
    await tester.pumpAndSettle();
    expect(find.text('確認用の作業員'), findsOneWidget);
    expect(tester.getTopLeft(find.text('取得済み資格')).dy, lessThan(230));
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(844 * 0.55));
    expect(find.text('ログイン中の本人の資格だけを表示します'), findsNothing);
    await tester.tap(find.byTooltip('資格登録の説明'));
    await tester.pumpAndSettle();
    expect(find.text('ログイン中の本人の資格だけを表示します'), findsOneWidget);
    expect(find.text('資格証写真の変更申請は準備中です。登録済み写真と資格情報登録は利用できます。'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('取得済み資格'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payroll confirmation stays visible and details do not consume the preview region', (tester) async {
    _phone(tester);
    // Keep the output guard active: this layout test never generates or prints
    // an unverified financial document merely to measure its allocated region.
    final detail = insuranceEvidenceFixture();
    (detail['tax_calculation'] as Map)['blocked'] = true;
    final before = jsonEncode(detail);
    final statement = PayrollStatementRecord(id: 'synthetic-statement',
      companyName: '確認用会社', workerName: '確認用社員', periodStart: DateTime(2026, 10),
      periodEnd: DateTime(2026, 10, 31), grossPay: 100, deductions: 10, netPay: 90,
      detail: detail, workflowState: 'draft', revision: 1);
    final status = PayrollConfirmationStatus.fromJson({
      'confirmation_open_date': '2026-10-31',
      'reviewers': [{'user_id': 'synthetic-reviewer', 'name': '確認者の氏名', 'position': 1, 'confirmed': false}],
    });
    final repository = PayrollStatementSourceRepository(
      readManagement: (_) async => [statement], readSelf: () async => [statement],
      readConfirmation: (_) async => status);
    await tester.pumpWidget(MaterialApp(home: PayrollStatementPreviewPage(
      statement: statement, sourceRepository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('確認 0/1名'), findsOneWidget);
    expect(find.text('確認者の氏名：未確認'), findsNothing);
    expect(find.text('確認開始：10/31'), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('payroll-preview-region'))).dy, lessThan(190));
    expect(tester.getSize(find.byKey(const ValueKey('payroll-preview-region'))).height, greaterThan(844 * 0.7));
    expect(find.textContaining('税計算の条件を確認してください。'), findsOneWidget);
    await tester.tap(find.text('確認 0/1名'));
    await tester.pumpAndSettle();
    expect(find.text('確認者の氏名：未確認'), findsOneWidget);
    expect(find.text('確認開始：10/31'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('プレビューの使い方'));
    await tester.pumpAndSettle();
    expect(find.text('2本指で拡大・縮小／拡大後はドラッグで移動'), findsOneWidget);
    expect(jsonEncode(detail), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending attendance keeps its count in a compact row and date guidance is still accessible', (tester) async {
    _phone(tester);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      PayrollPendingAttendancePanel(statementId: 'synthetic-statement', repository: _Pending(), onReturn: () async {}),
      const Expanded(child: SizedBox()),
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('未確定の勤務 1日'), findsOneWidget);
    expect(tester.getSize(find.byType(PayrollPendingAttendancePanel)).height, lessThanOrEqualTo(64));
    expect(find.text('10/13 勤務を確認'), findsNothing);
    await tester.tap(find.text('未確定の勤務 1日'));
    await tester.pumpAndSettle();
    expect(find.text('10/13 勤務を確認'), findsOneWidget);
    expect(find.textContaining('給与用の勤務記録が未確定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
