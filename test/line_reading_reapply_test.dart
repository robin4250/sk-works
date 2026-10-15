import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_import_repository.dart';
import 'package:sk_works/features/chat/line_reading_rule_application.dart';
import 'package:sk_works/features/chat/line_reading_rules.dart';
import 'package:sk_works/features/chat/line_reading_reapply_page.dart';

final source = <String,dynamic>{'id':'post','body':'10/15\n新宿 佐藤 残業1',
  'sent_at':'2026-10-15T08:00:00Z','sender_display_name':'投稿者','source_type':'history'};
const rules = [
  LineReadingRule(phrase:'新宿',kind:LineReadingKind.site,value:'新宿ビル工事'),
  LineReadingRule(phrase:'佐藤',kind:LineReadingKind.worker,value:'佐藤太郎'),
];
final sites = <Map<String,dynamic>>[{'id':'site','name':'新宿ビル工事','customer_id':'customer'}];
final workers = <Map<String,dynamic>>[{'id':'worker','name':'佐藤太郎'}];
Map<String,dynamic> automatic() => {...LineImportDraft.extract([source], DateTime(2026,10)).rows.single,
  'assumed_fields': {'early_hours':{'value':1,'reason':'仮の早出'}},'early_hours':1};

class _Auth extends Fake implements GoTrueClient { @override User? get currentUser => null; }
class _Client extends Fake implements SupabaseClient { @override GoTrueClient get auth => _Auth(); }
class _Repository extends LineImportRepository {
  _Repository() : super(_Client());
  final saves = <Map<String,dynamic>>[];
  @override Future<Map<String,dynamic>> load(String g,String t,DateTime m) async => {
    'can_edit':true,'revision':7,'features':{'invoice':true,'attendance':false},
    'source_kind':'history','source_messages':[source], 'candidate_rows':[automatic()], 'note_comparison':'元のメモ',
  };
  @override Future<List<LineReadingRule>> readingRules(String g) async => rules;
  @override Future<({List<Map<String,dynamic>> sites,List<Map<String,dynamic>> workers})> references(String g) async => (sites:sites,workers:workers);
  @override Future<Map<String,dynamic>> save(Map<String,dynamic> command) async { saves.add(command); return {}; }
}

void main() {
  test('legacy confirmed manual and changed provenance never produce applicable suggestions', () {
    final auto = automatic();
    final legacy = {...auto}..remove('reading_origin');
    for (final row in [legacy, {...auto,'confirmed':true}, {...auto,'edited':true},
      {...auto,'row_id':'manual:one'}, {...auto,'reading_origin':{'kind':'manual'}},
      {...auto,'source_fingerprint':'changed'}]) {
      expect(lineReadingSuggestions([row],rules), isEmpty);
    }
    expect(lineReadingSuggestions([auto],rules), hasLength(2));
    expect(lineReadingReapplyEligible(lineRepairAssumedQuantity(auto,'early_hours',2)), false);
  });
  test('one explicit field acceptance preserves source quantities assumptions and unselected field', () {
    final row=automatic(), proposals=lineReadingSuggestions([automatic()],rules);
    final saved=lineAcceptReadingSuggestions([row],proposals,
      {lineReadingSuggestionKey(proposals.first):'site'},sites:sites,workers:workers).single;
    expect(saved['site_name'],'新宿ビル工事'); expect(saved['site_id'],'site');
    expect(saved['customer_id'],'customer'); expect(saved['worker_name'],'佐藤');
    expect(saved['overtime_hours'],row['overtime_hours']);
    expect(saved['assumed_fields'],row['assumed_fields']);
    expect(saved['source_fingerprint'],row['source_fingerprint']);
    expect(saved['confirmed'],false); expect(lineReadingReapplyEligible(saved),false);
    expect(row['site_name'],'新宿');
  });
  test('ambiguous target IDs remain held and both fields can be explicitly accepted once', () {
    final row=automatic(), p=lineReadingSuggestions([automatic()],rules);
    final ambiguous=[...sites,{'id':'other','name':'新宿ビル工事'}];
    final held=lineAcceptReadingSuggestions([row],p,{lineReadingSuggestionKey(p.first):'site'},sites:ambiguous,workers:workers);
    expect(held.single,row);
    final saved=lineAcceptReadingSuggestions([row],p,
      {lineReadingSuggestionKey(p.first):'site',lineReadingSuggestionKey(p.last):'worker'},sites:sites,workers:workers).single;
    expect(saved['site_id'],'site'); expect(saved['worker_id'],'worker');
  });
  testWidgets('preview makes no writes until a field is accepted and explicitly saved', (tester) async {
    final repo=_Repository();
    await tester.pumpWidget(LineTestApp(home:Builder(builder:(context)=>Scaffold(body:FilledButton(
      onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>LineReadingReapplyPage(
        groupId:'group',month:DateTime(2026,10),repositoryOverride:repo))),child:const Text('開く'))))));
    await tester.tap(find.text('開く')); await tester.pumpAndSettle();
    expect(find.text('現場：新宿 → 新宿ビル工事'),findsOneWidget);
    expect(repo.saves,isEmpty);
    await tester.tap(find.text('この項目を採用').first); await tester.pumpAndSettle();
    expect(repo.saves,isEmpty);
    await tester.tap(find.text('採用した項目だけ保存')); await tester.pumpAndSettle();
    expect(repo.saves,hasLength(1));
    final command=repo.saves.single, row=(repo.saves.single['p_rows'] as List).single as Map;
    expect(command['p_expected_revision'],7); expect(command['p_confirmed'],false);
    expect(command['p_sources'],[source]); expect(row['site_id'],'site');
    expect(row['worker_name'],'佐藤'); expect(row['assumed_fields'],automatic()['assumed_fields']);
  });
}
