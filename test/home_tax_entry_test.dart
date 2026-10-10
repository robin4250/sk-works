import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/company_payroll_rates_home_entry.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/settings/company_payroll_rates_page.dart';

void main() {
  Widget home(String role) => MaterialApp(
    home: Scaffold(
      body: FriendlyHomeContent(
        identity: HomeIdentity(
          role: role,
          companyName: 'Test',
          displayName: 'Test',
        ),
        requiredDocumentAttention: const RequiredDocumentAttention(
          missingCount: 0,
          missingNames: [],
          needsLicense: false,
          needsQualification: false,
        ),
        moduleEnabled: (_) => false,
        showAttendanceReport: false,
        showTodayAttendance: false,
        onOpen: (_) async => fail('Tax entry must not require the admin menu'),
        onRefresh: () async {},
      ),
    ),
  );

  for (final role in ['viewer', 'admin', 'owner']) {
    testWidgets('$role can open tax rates directly from TOP', (tester) async {
      await tester.pumpWidget(home(role));
      expect(find.text('税率設定'), findsOneWidget);
      final entry = find.byType(CompanyPayrollRatesHomeEntry);
      final outer = tester.widget<Container>(
        find.descendant(of: entry, matching: find.byType(Container)).first,
      );
      expect((outer.decoration! as BoxDecoration).border, isNotNull);
      final inner = tester.widget<Material>(
        find.descendant(of: entry, matching: find.byType(Material)).first,
      );
      expect((inner.shape! as RoundedRectangleBorder).side.width, 1.8);
      await tester.tap(find.text('税率設定'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyPayrollRatesHomePage), findsOneWidget);
      // Missing session must remain a recoverable page, never admin settings.
      expect(find.text('再試行'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(FriendlyHomeContent), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final role in ['member', 'manager']) {
    testWidgets('$role retains existing tax access scope', (tester) async {
      await tester.pumpWidget(home(role));
      expect(find.byType(CompanyPayrollRatesHomeEntry), findsNothing);
    });
  }

  testWidgets(
    'resolved membership opens the existing tax page for that company',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyPayrollRatesHomePage(
            resolveCompanyId: () async => 'resolved-company',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<CompanyPayrollRatesPage>(
              find.byType(CompanyPayrollRatesPage),
            )
            .companyId,
        'resolved-company',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company lookup failure retries and completion after pop is safe',
    (tester) async {
      var calls = 0;
      final pending = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyPayrollRatesHomePage(
            resolveCompanyId: () {
              calls++;
              if (calls == 1) return Future.error(StateError('offline'));
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('会社情報を読み込めませんでした。'), findsOneWidget);
      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete('company-test');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
