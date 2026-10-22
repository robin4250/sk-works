import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_approval.dart';

void main() {
  CommonPayrollCanonicalApprovalPreview preview({bool activation = true, bool ready = true, int unresolved = 0}) =>
      CommonPayrollCanonicalApprovalPreview(payrollTypeLabel: '月給', startsOn: DateTime(2026, 10),
        targetCount: 3, excludedCount: 2, unresolvedCount: unresolved,
        activationRequired: activation, readyToPublish: ready, legacyCount: 2,
        reasons: const ['確定済み給与は除外', '個別設定の相違を確認']);
  Future<void> open(WidgetTester tester, {bool deployed = false, bool ready = true, int unresolved = 0}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body:
      TextButton(onPressed: () => showDialog<CommonPayrollCanonicalApproval>(context: context,
        builder: (_) => CommonPayrollCanonicalPublicationApprovalDialog(
          preview: preview(ready: ready, unresolved: unresolved), deploymentAvailable: deployed)),
        child: const Text('開く'))))));
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }
  testWidgets('undeployed contract cannot activate or publish even when preview is ready', (tester) async {
    await open(tester);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('canonical-publication-confirm'))).onPressed, isNull);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('canonical-publication-activation'))).onChanged, isNull);
  });
  testWidgets('explicit activation and selected-day consent are both required', (tester) async {
    await open(tester, deployed: true);
    FilledButton button() => tester.widget<FilledButton>(find.byKey(const ValueKey('canonical-publication-confirm')));
    expect(button().onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('canonical-publication-activation')));
    await tester.tap(find.byKey(const ValueKey('canonical-publication-activation')));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('canonical-publication-selected-days')));
    await tester.tap(find.byKey(const ValueKey('canonical-publication-selected-days')));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
  });
  testWidgets('unresolved preview cannot be confirmed and reasons start collapsed', (tester) async {
    await open(tester, deployed: true, unresolved: 1);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('canonical-publication-confirm'))).onPressed, isNull);
    expect(find.text('確定済み給与は除外').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('canonical-publication-reasons')));
    await tester.pumpAndSettle();
    expect(find.text('確定済み給与は除外').hitTestable(), findsOneWidget);
  });
}
