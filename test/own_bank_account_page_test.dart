import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_bank_account_page.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';

class Bank extends ChangeNotifier implements OwnBankAccountGateway {
  bool current=true,registered=false,failRead=false;
  int writes=0;
  OwnBankAccountInput? submitted;
  Completer<OwnBankAccountState>? pending;
  @override bool get isCurrent=>current;
  @override Future<OwnBankAccountState> load() async {
    if(failRead) throw StateError('Synthetic read denied');
    return OwnBankAccountState(registered:registered);
  }
  @override Future<OwnBankAccountState> register(OwnBankAccountInput input) async {
    writes++;submitted=input;
    return pending==null ? const OwnBankAccountState(registered:true) : await pending!.future;
  }
  void invalidate() {current=false;notifyListeners();}
  @override Future<void> close() async {dispose();}
}
Future<void> show(WidgetTester t,Bank bank) async {
  await t.pumpWidget(MaterialApp(home:OwnBankAccountPage(workerId:'synthetic-worker',companyId:'synthetic-company',gateway:bank)));
  await t.pumpAndSettle();
}
Future<void> fill(WidgetTester t) async {
  for(final entry in {'bank-name':'SYNTHETIC BANK','bank-branch':'SYNTHETIC BRANCH','bank-number':'００００００１','bank-holder':'SYNTHETIC HOLDER'}.entries) {
    await t.enterText(find.byKey(Key(entry.key)),entry.value);
  }
  await t.ensureVisible(find.widgetWithText(FilledButton,'銀行口座情報を登録'));
}
void main() {
  testWidgets('bank form validates seven digits and explicitly saves typed fields without a photo', (t) async {
    final bank=Bank();await show(t,bank);
    await fill(t);await t.enterText(find.byKey(const Key('bank-number')),'123');
    await t.ensureVisible(find.byType(FilledButton));await t.tap(find.byType(FilledButton));await t.pumpAndSettle();
    expect(bank.writes,0);expect(find.text('口座番号は7桁で入力してください。'),findsOneWidget);
    await t.enterText(find.byKey(const Key('bank-number')),'００００００１');
    await t.ensureVisible(find.byType(FilledButton));await t.tap(find.byType(FilledButton));await t.pumpAndSettle();
    expect(bank.writes,1);expect(bank.submitted!.accountNumber,'0000001');
    expect(find.text('銀行口座情報は登録済みです。'),findsOneWidget);expect(find.byType(TextFormField),findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('existing private account is registered and retained without offering a duplicate write', (t) async {
    final bank=Bank()..registered=true;await show(t,bank);
    expect(find.text('銀行口座情報は登録済みです。'),findsOneWidget);expect(find.byType(TextFormField),findsNothing);
    expect(find.byType(FilledButton),findsNothing);expect(bank.writes,0);await t.pumpWidget(const SizedBox());
  });
  testWidgets('denied read is unknown and cannot enable registration', (t) async {
    final bank=Bank()..failRead=true;await show(t,bank);
    expect(find.text('口座の登録状態を確認できません。再読み込みしてください。'),findsOneWidget);
    expect(find.byType(TextFormField),findsNothing);expect(bank.writes,0);await t.pumpWidget(const SizedBox());
  });
  testWidgets('auth boundary clears typed account and discards late success', (t) async {
    final bank=Bank()..pending=Completer<OwnBankAccountState>();await show(t,bank);await fill(t);
    await t.tap(find.byType(FilledButton));await t.pump();bank.invalidate();
    bank.pending!.complete(const OwnBankAccountState(registered:true));await t.pumpAndSettle();
    expect(find.text('銀行口座情報を登録しました'),findsNothing);expect(find.byType(TextFormField),findsNothing);
    expect(bank.writes,1);await t.pumpWidget(const SizedBox());
  });
}
