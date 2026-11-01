import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/profile/profile_own_bank_entry.dart';
import 'package:sk_works/features/people/own_bank_account_page.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';

const worker = '40000000-0000-0000-0000-000000000001';
const company = '30000000-0000-0000-0000-000000000001';
class FixtureBank extends ChangeNotifier implements OwnBankAccountGateway {
  FixtureBank({this.registered = false});
  final bool registered;
  bool current = true;
  int writes = 0;
  @override bool get isCurrent => current;
  @override Future<OwnBankAccountState> load() async {
    if (!current) throw StateError('Synthetic scope retired');
    return OwnBankAccountState(registered: registered);
  }
  @override Future<OwnBankAccountState> register(OwnBankAccountInput input) async {
    writes++;
    throw StateError('Fixture writes forbidden');
  }
  void retireScope() { current = false; notifyListeners(); }
  @override Future<void> close() async { dispose(); }
}
void main() {
  testWidgets('profile tile uses real canonical route with exact own identifiers', (t) async {
    final bank = FixtureBank();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
      workerId: worker, companyId: company, bankGateway: bank))));
    await t.tap(find.byKey(const Key('profile-own-bank-entry')));
    await t.pumpAndSettle();
    final page = t.widget<OwnBankAccountPage>(find.byType(OwnBankAccountPage));
    expect(page.workerId, worker); expect(page.companyId, company);
    expect(find.byKey(const Key('bank-name')), findsOneWidget);
    expect(find.byKey(const Key('bank-number')), findsOneWidget);
    expect(bank.writes, 0);
    await t.pumpWidget(const SizedBox()); await bank.close();
  });

  testWidgets('uppercase UUIDs retain canonical repository compatibility', (t) async {
    final bank = FixtureBank(registered: true);
    const upperWorker = '4A000000-0000-0000-0000-000000000001';
    const upperCompany = '3B000000-0000-0000-0000-000000000001';
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
      workerId: upperWorker, companyId: upperCompany, bankGateway: bank))));
    await t.tap(find.byKey(const Key('profile-own-bank-entry'))); await t.pumpAndSettle();
    final page = t.widget<OwnBankAccountPage>(find.byType(OwnBankAccountPage));
    expect(page.workerId, upperWorker); expect(page.companyId, upperCompany);
    expect(bank.writes, 0);
    await t.pumpWidget(const SizedBox()); await bank.close();
  });
  testWidgets('missing or invalid identity cannot navigate or guess another target', (t) async {
    for (final ids in [(null, company), (worker, null), ('other', company), (worker, '')]) {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
        workerId: ids.$1, companyId: ids.$2))));
      final tile = t.widget<ListTile>(find.byKey(const Key('profile-own-bank-entry')));
      expect(tile.enabled, isFalse); expect(tile.onTap, isNull);
      expect(find.byType(OwnBankAccountPage), findsNothing);
    }
  });
  testWidgets('scope retirement clears canonical form and prevents save', (t) async {
    final bank = FixtureBank();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
      workerId: worker, companyId: company, bankGateway: bank))));
    await t.tap(find.byKey(const Key('profile-own-bank-entry'))); await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('bank-name')), 'SYNTHETIC');
    bank.retireScope(); await t.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('ログイン状態が変わりました。画面を開き直してください。'), findsOneWidget);
    expect(bank.writes, 0);
    await t.pumpWidget(const SizedBox()); await bank.close();
  });
  testWidgets('registered route preserves metadata-only initial registration limitation', (t) async {
    final bank = FixtureBank(registered: true);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
      workerId: worker, companyId: company, bankGateway: bank))));
    await t.tap(find.byKey(const Key('profile-own-bank-entry'))); await t.pumpAndSettle();
    expect(find.text('銀行口座情報は登録済みです。'), findsOneWidget);
    expect(find.text('登録済みの口座情報は保持しています。この画面から変更・削除は行いません。'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing); expect(bank.writes, 0);
    await t.pumpWidget(const SizedBox()); await bank.close();
  });
  testWidgets('return refreshes profile only for same session company and worker', (t) async {
    final bank = FixtureBank(registered: true), session = Object();
    var refreshed = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
      workerId: worker, companyId: company, bankGateway: bank,
      currentScope: () => ProfileOwnBankScope(session: session, workerId: worker, companyId: company),
      onReturned: () async { refreshed++; }))));
    await t.tap(find.byKey(const Key('profile-own-bank-entry'))); await t.pumpAndSettle();
    expect(refreshed, 0);
    await t.pageBack(); await t.pumpAndSettle();
    expect(refreshed, 1); expect(bank.writes, 0);
    await t.pumpWidget(const SizedBox()); await bank.close();
  });
  for (final change in ['actor-session', 'company', 'worker']) {
    testWidgets('return after $change change cannot refresh the old profile', (t) async {
      final bank = FixtureBank(registered: true);
      Object session = Object(); var currentWorker = worker, currentCompany = company, refreshed = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ProfileOwnBankEntry(
        workerId: worker, companyId: company, bankGateway: bank,
        currentScope: () => ProfileOwnBankScope(session: session, workerId: currentWorker, companyId: currentCompany),
        onReturned: () async { refreshed++; }))));
      await t.tap(find.byKey(const Key('profile-own-bank-entry'))); await t.pumpAndSettle();
      if (change == 'actor-session') { session = Object(); }
      if (change == 'company') { currentCompany = worker; }
      if (change == 'worker') { currentWorker = company; }
      await t.pageBack(); await t.pumpAndSettle();
      expect(refreshed, 0); expect(bank.writes, 0);
      await t.pumpWidget(const SizedBox()); await bank.close();
    });
  }

}
