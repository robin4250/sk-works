import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Reports extends DailyReportMonthRepository {
  _Reports(SupabaseClient client) : super(client,DailyReportRepository.forTesting(client));
  bool changed = false;
  @override
  String get actor => 'actor';
  @override
  void checkActor(String captured) {
    if (changed || captured != actor) throw StateError('account changed');
  }
  @override
  Future<List<DailyReportMonthEntry>> list(DateTime month,{String? workerId}) async => [
    DailyReportMonthEntry(id:'saved',date:DateTime(2026,10,12),name:'既存ルート',status:'signed',routeId:'route'),
  ];
}

void main() {
  late SupabaseClient client;
  setUp(() => client = SupabaseClient('https://example.invalid','fixture',
    authOptions: const AuthClientOptions(autoRefreshToken:false)));
  tearDown(() async => client.dispose());
  testWidgets('a past route day opens quantity submission for that selected worker and date', (tester) async {
    final repository = _Reports(client);
    String? worker;
    DateTime? date;
    await tester.pumpWidget(MaterialApp(home: DailyReportMonthPage(
      initialDate:DateTime(2026,10,12),workerId:'selected-worker',repositoryForTesting:repository,
      quantityBuilderForTesting:(id,day) { worker=id;date=day;return const Scaffold(body:Text('数量画面')); })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('請求数量を申請'));await tester.pumpAndSettle();
    expect(worker,'selected-worker');expect(date,DateTime(2026,10,12));
    expect(find.text('数量画面'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('account change prevents opening the cached route day submission', (tester) async {
    final repository = _Reports(client);
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: DailyReportMonthPage(
      initialDate:DateTime(2026,10,12),workerId:'selected-worker',repositoryForTesting:repository,
      quantityBuilderForTesting:(id,day) { opened=true;return const SizedBox(); })));
    await tester.pumpAndSettle();repository.changed=true;
    await tester.tap(find.text('請求数量を申請'));await tester.pumpAndSettle();
    expect(opened,false);
    expect(find.text('請求数量を開けませんでした。ログインを確認して再読み込みしてください。'),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
