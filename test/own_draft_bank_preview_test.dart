import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/own_draft_bank_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/payroll/payroll_statements_page.dart';
import 'own_draft_bank_admission_test.dart' as fixture;
class BankGateway extends ChangeNotifier implements OwnDraftBankGateway {
 @override bool isCurrent=true;
 @override Future<OwnDraftBankAdmission> read(PayrollStatementRecord statement)async=>throw StateError('synthetic bank offline');
 @override Future<void> close()async{}
}
void main(){
 testWidgets('bank failure keeps payroll money visible, never unregistered PDF or print/share',(tester)async{
  final own=asOwnDraftStatement(fixture.row());final gateway=BankGateway();
  final source=PayrollStatementSourceRepository(readManagement:(_)async=>throw const PostgrestException(message:'synthetic',code:'42501'),readSelf:()async=>[own],readConfirmation:(_)async=>throw StateError('must not request confirmation'));
  await tester.pumpWidget(MaterialApp(home:PayrollStatementPreviewPage(statement:own,sourceRepository:source,ownBankGateway:gateway)));
  await tester.pumpAndSettle();
  expect(find.textContaining('支給額 100円'),findsOneWidget);expect(find.textContaining('差引支給額 90円'),findsOneWidget);
  expect(find.textContaining('未登録とは判断せず'),findsOneWidget);expect(find.byType(PdfPreview),findsNothing);
  expect(find.text('未登録'),findsNothing);
 });
}
