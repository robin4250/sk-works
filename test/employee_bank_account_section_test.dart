import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/employee_bank_account_repository.dart';
import 'package:sk_works/features/people/employee_bank_account_section.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
import 'package:sk_works/features/people/own_bank_account_page.dart';
const company='30000000-0000-0000-0000-000000000001';
const worker='40000000-0000-0000-0000-000000000001';
const other='40000000-0000-0000-0000-000000000002';
class Own extends ChangeNotifier implements OwnBankAccountGateway {
  @override bool get isCurrent=>true;
  @override Future<OwnBankAccountState> load() async=>const OwnBankAccountState(registered:false);
  @override Future<OwnBankAccountState> register(OwnBankAccountInput input) async=>const OwnBankAccountState(registered:true);
  @override Future<void> close() async {dispose();}
}
class Gateway extends ChangeNotifier implements EmployeeBankAccountGateway {
  String selected=worker;bool current=true,enabled=true,registered=false,self=false,available=true;
  int writes=0,passwords=0;OwnBankAccountInput? saved;Completer<EmployeeBankAccountState>? delayed;
  final own=Own();
  EmployeeBankAccountState get value=>EmployeeBankAccountState(companyId:company,workerId:selected,self:self,available:available,
    managerEnabled:enabled,registered:registered,updatedAt:registered?DateTime.utc(2026,10,29):null);
  @override bool get isCurrent=>current;
  @override OwnBankAccountGateway? get selfGateway=>self?own:null;
  @override Future<EmployeeBankAccountState> load() async=>delayed==null?value:await delayed!.future;
  @override Future<EmployeeBankAccountState> register(OwnBankAccountInput input,{required Future<String?> Function() requestPassword}) async {
    passwords++;final secret=await requestPassword();
    if(secret==null||!current)throw StateError('Synthetic cancelled');
    expectSync(secret,'synthetic-primary');writes++;saved=input;registered=true;return value;
  }
  void invalidate(){current=false;notifyListeners();}
  @override Future<void> close() async {own.dispose();dispose();}
}
Future<void> open(WidgetTester t,Gateway gateway,{String selected=worker}) async {
  await t.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[EmployeeBankAccountSection(
    companyId:company,workerId:selected,employeeName:'合成社員',gateway:gateway)])))));
  await t.pumpAndSettle();
}
Future<void> form(WidgetTester t) async {
  await t.tap(find.text('この社員の銀行口座を登録'));await t.pumpAndSettle();
  for(final entry in {'employee-bank-name':'SYNTHETIC BANK','employee-bank-branch':'SYNTHETIC BRANCH',
    'employee-bank-holder':'SYNTHETIC HOLDER','employee-bank-number':'００００００１'}.entries) {
    await t.enterText(find.byKey(Key(entry.key)),entry.value);
  }
  await t.ensureVisible(find.text('本パスワードで確認して登録'));
}
void main(){
  testWidgets('manager OFF never opens a self form or offers a pretend registration', (t) async {
    final gateway=Gateway()..enabled=false;await open(t,gateway);
    expect(find.text('管理者による初回登録は導入準備中です。'),findsOneWidget);
    expect(find.text('この社員の銀行口座を登録'),findsNothing);expect(find.text('本人の銀行口座を登録'),findsNothing);
    expect(find.byType(TextFormField),findsNothing);expect(gateway.writes,0);await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('exact selected employee completes explicit primary password initial registration', (t) async {
    final gateway=Gateway();await open(t,gateway);await form(t);
    await t.tap(find.text('本パスワードで確認して登録'));await t.pump(const Duration(milliseconds:300));
    expect(gateway.writes,0);expect(find.text('初回口座登録の本人確認'),findsOneWidget);
    await t.enterText(find.byKey(const Key('employee-bank-primary-password')),'synthetic-primary');
    await t.tap(find.text('本人確認して登録'));await t.pumpAndSettle();
    expect(gateway.writes,1);expect(gateway.saved!.accountNumber,'0000001');
    expect(find.text('対象社員の銀行口座情報を登録しました'),findsOneWidget);
    await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('existing account shows retained without a duplicate registration button', (t) async {
    final gateway=Gateway()..registered=true;await open(t,gateway);
    expect(find.text('登録済みの銀行口座情報は保持しています。'),findsOneWidget);
    expect(find.text('この社員の銀行口座を登録'),findsNothing);expect(gateway.writes,0);await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('wrong worker response cannot be shown or substituted into self registration', (t) async {
    final gateway=Gateway()..selected=other..self=true;await open(t,gateway);
    expect(find.text('本人の銀行口座を登録'),findsNothing);expect(find.text('この社員の銀行口座を登録'),findsNothing);
    expect(find.textContaining('登録状態を確認できません'),findsOneWidget);await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('verified self entry retains selected worker and company when using existing self API', (t) async {
    final gateway=Gateway()..self=true;await open(t,gateway);
    await t.tap(find.text('本人の銀行口座を登録'));await t.pumpAndSettle();
    final page=t.widget<OwnBankAccountPage>(find.byType(OwnBankAccountPage));expect(page.workerId,worker);expect(page.companyId,company);
    expect(find.byKey(const Key('employee-bank-number')),findsNothing);expect(find.byKey(const Key('bank-number')),findsOneWidget);
    await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('auth invalidation clears bank/password fields and cancels late write', (t) async {
    final gateway=Gateway();await open(t,gateway);await form(t);
    await t.tap(find.text('本パスワードで確認して登録'));await t.pump(const Duration(milliseconds:300));
    await t.enterText(find.byKey(const Key('employee-bank-primary-password')),'synthetic-primary');gateway.invalidate();await t.pump();
    final password=t.widget<TextField>(find.byKey(const Key('employee-bank-primary-password')));expect(password.controller!.text,isEmpty);
    await t.tap(find.text('キャンセル'));await t.pumpAndSettle();
    expect(gateway.writes,0);expect(find.byKey(const Key('employee-bank-number')),findsNothing);
    expect(find.text('対象社員の銀行口座情報を登録しました'),findsNothing);await t.pumpWidget(const SizedBox());await gateway.close();
  });
  testWidgets('late previous employee response cannot replace a newly selected employee', (t) async {
    final first=Gateway()..delayed=Completer<EmployeeBankAccountState>();
    await t.pumpWidget(MaterialApp(home:EmployeeBankAccountSection(companyId:company,workerId:worker,employeeName:'旧合成社員',gateway:first)));await t.pump();
    final next=Gateway()..selected=other..registered=true;
    await t.pumpWidget(MaterialApp(home:EmployeeBankAccountSection(companyId:company,workerId:other,employeeName:'新合成社員',gateway:next)));await t.pumpAndSettle();
    first.delayed!.complete(first.value);await t.pumpAndSettle();
    expect(find.text('対象社員：新合成社員'),findsOneWidget);expect(find.text('登録済みの銀行口座情報は保持しています。'),findsOneWidget);
    expect(find.text('この社員の銀行口座を登録'),findsNothing);await t.pumpWidget(const SizedBox());await first.close();await next.close();
  });
}
