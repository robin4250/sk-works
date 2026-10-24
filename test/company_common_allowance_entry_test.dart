import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/company_common_allowance_entry_page.dart';
import 'package:sk_works/features/payroll/company_common_allowance_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_page.dart';
import 'package:sk_works/features/settings/company_allowance_identity_page.dart';

import 'company_common_allowance_connected_test.dart' as fixture;

void main() {
  test('allowance entry alone changes route; existing tax and rates remain', () {
    final source = File('lib/app_v2.dart').readAsStringSync();
    final allowance = source.split("case 'company_common_allowances':").last
        .split("case 'company_tax_rates':").first;
    expect(allowance, contains('CompanyCommonAllowanceEntryPage()'));
    expect(allowance, contains('SecondaryProtectedPage'));
    expect(source.split("case 'company_tax_rates':").last
        .split("case 'vehicle_select':").first,
        contains('CompanyPayrollRatesHomePage()'));
    expect(source, isNot(contains('CompanyCommonSettingsPage')));
  });

  testWidgets('multiple memberships require explicit company selection', (tester) async {
    final built = <String>[];
    await tester.pumpWidget(MaterialApp(home: CompanyCommonAllowanceEntryPage(
      currentActor: () => 'actor',
      scopeLoader: () async => const [
        CompanyCommonAllowanceScope('first', '会社A', true),
        CompanyCommonAllowanceScope('second', '会社B', false),
      ],
      allowancesBuilder: (_, id) { built.add(id); return Text('selected:$id'); },
    )));
    await tester.pumpAndSettle();
    expect(built, isEmpty);
    await tester.tap(find.text('会社B'));
    await tester.pumpAndSettle();
    expect(find.text('selected:second'), findsOneWidget);
    expect(built.toSet(), {'second'});
  });

  for (final editable in [true, false]) {
    testWidgets('registered item management stays inside selected payroll scope: $editable', (tester) async {
      await tester.pumpWidget(MaterialApp(home: CompanyCommonAllowanceEntryPage(
        currentActor: () => 'actor',
        scopeLoader: () async => [CompanyCommonAllowanceScope('first', '会社A', editable)],
        allowancesBuilder: (_, id) => Text('selected:$id'),
      )));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('common-allowance-registered-items'));
      expect(entry, editable ? findsOneWidget : findsNothing);
      if (editable) {
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(tester.widget<CompanyAllowanceIdentityPage>(find.byType(CompanyAllowanceIdentityPage)).companyId, 'first');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('stale membership response cannot open previous actor company', (tester) async {
    var actor = 'actor';
    final pending = Completer<List<CompanyCommonAllowanceScope>>();
    var built = false;
    await tester.pumpWidget(MaterialApp(home: CompanyCommonAllowanceEntryPage(
      currentActor: () => actor, scopeLoader: () => pending.future,
      allowancesBuilder: (_, id) { built = true; return Text(id); },
    )));
    actor = 'other';
    pending.complete(const [CompanyCommonAllowanceScope('first', '会社A', true)]);
    await tester.pumpAndSettle();
    expect(built, isFalse);
    expect(find.textContaining('ログイン状態が変わりました'), findsOneWidget);
  });

  for (final code in ['PGRST202', '42501', 'network']) {
    testWidgets('read failure $code never enables registration or sends writes', (tester) async {
      final calls = <String>[];
      final repo = SupabaseCompanyCommonAllowanceRepository.forTesting(
        actor: () => fixture.actor,
        invoke: (name, args) async {
          calls.add(name);
          throw PostgrestException(message: 'fixture unavailable', code: code);
        },
      );
      await tester.pumpWidget(MaterialApp(home: CompanyCommonPayrollPage(
        companyId: fixture.company, repository: repo,
        pendingStore: fixture.MemoryStore(),
      )));
      await tester.pumpAndSettle();
      expect(calls, ['read_company_common_allowances_admin']);
      expect(find.textContaining('入力・保存は開始していません'), findsOneWidget);
      expect(find.text('登録'), findsNothing);
      expect(find.text('追加'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
