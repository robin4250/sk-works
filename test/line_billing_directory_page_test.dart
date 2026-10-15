import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/line_billing_directory_page.dart';
import 'package:sk_works/features/chat/line_import_repository.dart';
import 'package:sk_works/features/chat/line_import_page.dart';

class _Auth extends Fake implements GoTrueClient {
  @override
  User? get currentUser => null;
}
class _Client extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _Auth();
}
class _Repository extends LineImportRepository {
  _Repository() : super(_Client());
  @override
  Future<List<Map<String,dynamic>>> destinations() async => [{
    'id':'g', 'name':'分析履歴', 'months':[
      {'month':'2026-08-01','row_count':1}, {'month':'2026-09-01','row_count':1},
    ],
  }];
  @override
  Future<Map<String,dynamic>> load(String groupId,String target,DateTime month) async => {
    'candidate_rows':[{'site_id':'s','site_name':'現場A','confirmed':true}],
  };
}
void main() {
  testWidgets('month entry shows imported months newest first and passes actual saved identity', (tester) async {
    await tester.pumpWidget(LineTestApp(home:LineBillingDirectoryPage(
      kind:LineBillingDirectoryKind.monthly, repositoryOverride:_Repository())));
    await tester.pumpAndSettle();
    final tiles=tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title as Text).data,'2026年9月');
    expect(find.byType(DropdownButtonFormField<String>),findsNothing);
    await tester.tap(find.text('2026年9月'));
    await tester.pumpAndSettle();
    final page=tester.widget<LineImportPage>(find.byType(LineImportPage));
    expect(page.initialGroupId,'g');
    expect(page.initialMonth,DateTime(2026,9));
  });
  testWidgets('rate entry groups the same site across imported months', (tester) async {
    await tester.pumpWidget(LineTestApp(home:LineBillingDirectoryPage(
      kind:LineBillingDirectoryKind.rates, repositoryOverride:_Repository())));
    await tester.pumpAndSettle();
    expect(find.text('現場A'),findsOneWidget);
    expect(find.byType(ListTile),findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>),findsNothing);
  });
}
