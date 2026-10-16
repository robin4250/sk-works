import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_common_settings_page.dart';

class DraftEditor extends StatefulWidget {
 const DraftEditor(this.label, {super.key});
 final String label;
 @override State<DraftEditor> createState() => _DraftEditorState();
}
class _DraftEditorState extends State<DraftEditor> {
 final controller = TextEditingController();
 @override void dispose() { controller.dispose(); super.dispose(); }
 @override Widget build(BuildContext context) => TextField(key: ValueKey(widget.label), controller: controller);
}
Widget page({String? company, Future<List<CompanyCommonSettingsScope>> Function()? loader, String? Function()? actor}) => MaterialApp(home: CompanyCommonSettingsPage(companyId: company,
 currentActor: actor ?? () => 'actor', scopeLoader: loader ?? () async => [const CompanyCommonSettingsScope('company-a', '会社A', true)],
 allowancesBuilder: (_, id) => DraftEditor('allowances-$id'), taxBuilder: (_, id) => DraftEditor('tax-$id')));
void main() {
 testWidgets('both tabs use selected company and retain unsaved drafts across switching', (tester) async {
  await tester.pumpWidget(page(company: 'company-a')); await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('allowances-company-a')), '未保存の手当');
  await tester.tap(find.text('消費税・福利厚生費')); await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('tax-company-a')), '未保存の税率');
  await tester.tap(find.text('手当')); await tester.pumpAndSettle(); expect(find.text('未保存の手当'), findsOneWidget);
  await tester.tap(find.text('消費税・福利厚生費')); await tester.pumpAndSettle(); expect(find.text('未保存の税率'), findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('multiple legitimate memberships require explicit company choice', (tester) async {
  await tester.pumpWidget(page(loader: () async => [const CompanyCommonSettingsScope('company-a', '会社A', true), const CompanyCommonSettingsScope('company-b', '会社B', false)]));
  await tester.pumpAndSettle(); expect(find.byType(TextField), findsNothing);
  await tester.tap(find.text('会社B')); await tester.pumpAndSettle(); expect(find.byKey(const ValueKey('allowances-company-b')), findsOneWidget);
  await tester.tap(find.text('消費税・福利厚生費')); await tester.pumpAndSettle(); expect(find.byKey(const ValueKey('tax-company-b')), findsOneWidget);
  await tester.pumpWidget(const SizedBox());
 });
 testWidgets('background draft remains hidden through failed reauthorization then restores', (tester) async {
  var deny = false;
  await tester.pumpWidget(page(loader: () async { if (deny) throw StateError('offline'); return [const CompanyCommonSettingsScope('company-a','会社A',true)]; })); await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('allowances-company-a')), '背景で保護');
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
  expect(find.text('背景で保護'), findsNothing); expect(find.text('背景で保護', skipOffstage: false), findsOneWidget);
  deny = true;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
  expect(find.text('背景で保護'), findsNothing); expect(find.text('背景で保護', skipOffstage: false), findsOneWidget);
  deny = false; await tester.tap(find.text('再確認')); await tester.pumpAndSettle(); expect(find.text('背景で保護'), findsOneWidget); await tester.pumpWidget(const SizedBox());
 });
 testWidgets('late membership response cannot expose a previous actor company', (tester) async {
  final pending = Completer<List<CompanyCommonSettingsScope>>(); var who = 'actor';
  await tester.pumpWidget(page(loader: () => pending.future, actor: () => who)); await tester.pump();
  who = 'other'; pending.complete([const CompanyCommonSettingsScope('company-a','会社A',true)]); await tester.pumpAndSettle();
  expect(find.byType(TextField), findsNothing); expect(find.textContaining('開き直してください'), findsOneWidget); await tester.pumpWidget(const SizedBox());
 });
 test('menu and payroll routes share protected company settings destination', () {
  final settings = File('lib/features/settings/settings_page.dart').readAsStringSync();
  final app = File('lib/app_v2.dart').readAsStringSync();
  final entry = File('lib/features/settings/company_common_settings_entry.dart').readAsStringSync();
  expect(settings, contains('CompanyCommonSettingsEntry(companyId: _companyId!, canManageCompany: _canManageCompany)'));
  expect(settings, isNot(contains('CompanyAllowanceIdentityEntry('))); expect(settings, isNot(contains('CompanyRateSettingsPage(')));
  expect(entry, contains('SecondaryProtectedPage(')); expect(entry, contains('CompanyCommonSettingsPage(companyId: companyId)'));
  expect(app, contains("case 'company_common_allowances':")); expect(app, contains('child: CompanyCommonSettingsPage()'));
  expect(app, contains("if (!_nestedActionKeys.contains('company_common_allowances')) return;"));
 });
}
