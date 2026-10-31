import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'attendance_unrecorded_punches_test.dart' as fixture;

class BulkCalendarFixture extends fixture.PageFixture {
  BulkCalendarFixture(super.client);
  final markReads = <({String worker, DateTime month})>[];
  Future<Map<int,Set<String>>> Function(String,DateTime)? onMarks;
  @override Future<Map<int,Set<String>>> loadMonthMarks({required String workerId,required DateTime month}) {
    markReads.add((worker:workerId,month:month));
    return onMarks?.call(workerId,month) ?? Future.value(workerId==fixture.worker
      ? {3:{'work'},4:{'punch'},5:{'leave'}} : <int,Set<String>>{});
  }
}

void main() {
  late fixture.Fixture wire;
  late BulkCalendarFixture repository;
  setUp(() async {
    wire=fixture.Fixture();
    await wire.start();
    repository=BulkCalendarFixture(wire.client);
  });
  tearDown(() async { await wire.client.dispose(); });

  Future<void> mount(WidgetTester tester,{double width=430,double scale=1,ValueNotifier<bool>? scopeVisible}) async {
    tester.view.physicalSize=Size(width,932);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),
      home:scopeVisible==null?AttendanceManagementPage(repository:repository):ValueListenableBuilder<bool>(
        valueListenable:scopeVisible,builder:(_,visible,__)=>visible
          ? AttendanceManagementPage(repository:repository)
          : const Scaffold(body:Center(child:Text('親の認証境界'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab,'一括'));
    await tester.pumpAndSettle();
  }
  Finder scrollable()=>find.descendant(of:find.byType(ListView).last,matching:find.byType(Scrollable)).first;
  Finder day(int number)=>find.byKey(ValueKey('bulk-calendar-day-$number'));
  Finder deleteButton()=>find.widgetWithText(OutlinedButton,'選択範囲を一括削除');
  Future<void> see(WidgetTester tester,Finder finder,{bool up=false}) async {
    await tester.scrollUntilVisible(finder,up?-220:220,scrollable:scrollable());
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  Future<void> selectWorker(WidgetTester tester,String label) async {
    final finder=find.widgetWithText(CheckboxListTile,label);
    await see(tester,finder,up:true);
    await tester.tap(finder);
    await tester.pump();
  }
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
  Iterable<Map<String,dynamic>> writes()=>wire.calls
    .where((r)=>r.url.path.endsWith('/force_manage_attendance'))
    .map((r)=>Map<String,dynamic>.from(jsonDecode(r.body) as Map));

  for(final dimensions in [(430.0,1.0),(320.0,2.0)]) {
    testWidgets('real bulk calendar shows scoped marks and separate selection at ${dimensions.$1}/scale${dimensions.$2}',(tester) async {
      await mount(tester,width:dimensions.$1,scale:dimensions.$2);
      await selectWorker(tester,'検証社員');
      await tester.pumpAndSettle();
      final legend=find.text('青● 出勤　橙● 打刻のみ　緑● 承認済み有給');
      await see(tester,legend);expect(legend,findsOneWidget);
      await see(tester,day(3));
      expect(find.text('●出1/1'),findsOneWidget);
      expect(find.text('●打1/1'),findsOneWidget);
      expect(find.text('●有1/1'),findsOneWidget);
      expect(tester.widget<FilterChip>(day(3)).selected,false);
      await tester.tap(day(3));await tester.pump();
      expect(tester.widget<FilterChip>(day(3)).selected,true);
      expect(find.text('●出1/1'),findsOneWidget);
      expect(writes(),isEmpty);
      expect(tester.takeException(),isNull);
      await finish(tester);
    });
  }

  testWidgets('multiple workers show per-kind counts and changing workers clears dates',(tester) async {
    repository.onMarks=(worker,month) async => worker==fixture.worker
      ? {3:{'work'},4:{'punch'},5:{'leave'}} : {3:{'work'},4:{'work'}};
    await mount(tester);
    await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await selectWorker(tester,'別社員');await tester.pumpAndSettle();
    await see(tester,day(3));
    expect(find.text('●出2/2'),findsOneWidget);
    expect(find.text('●打1/2'),findsOneWidget);
    expect(find.text('●有1/2'),findsOneWidget);
    expect(tester.widget<FilterChip>(day(3)).selected,false);
    expect(repository.markReads.map((read)=>read.worker),containsAll([fixture.worker,fixture.actor]));
    expect(writes(),isEmpty);
    await finish(tester);
  });

  testWidgets('owned calendar rebuilds counts and preserves entered form text across normal month reads',(tester) async {
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    final note=find.widgetWithText(TextField,'勤怠メモ');
    await see(tester,note);await tester.enterText(note,'保持する入力');
    FocusManager.instance.primaryFocus?.unfocus();await tester.pumpAndSettle();
    final next=find.byTooltip('一括カレンダーの次の月');
    await see(tester,next,up:true);await tester.tap(next);await tester.pumpAndSettle();
    await see(tester,day(3));expect(find.text('●出1/1'),findsOneWidget);
    await tester.tap(day(3));await tester.pump();
    expect(tester.widget<FilterChip>(day(3)).selected,true);
    await see(tester,note);
    expect(tester.widget<TextField>(note).controller!.text,'保持する入力');
    expect(writes(),isEmpty);await finish(tester);
  });

  testWidgets('empty success differs from partial-batch failure and cannot delete unknown data',(tester) async {
    repository.onMarks=(worker,month) async => {};
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    final empty=find.text('選択した従業員のこの月の出勤・打刻・承認済み有給の記録はありません。');
    await see(tester,empty);expect(empty,findsOneWidget);
    await see(tester,day(3));
    expect(tester.widget<FilterChip>(day(3)).onSelected,isNotNull);
    repository.onMarks=(worker,month) async {
      if(worker==fixture.actor)throw StateError('synthetic unavailable');
      return {3:{'work'}};
    };
    await selectWorker(tester,'別社員');await tester.pumpAndSettle();await see(tester,day(3));
    expect(find.text('●出1/2'),findsNothing);
    expect(tester.widget<FilterChip>(day(3)).onSelected,isNull);
    await see(tester,deleteButton());
    expect(tester.widget<OutlinedButton>(deleteButton()).onPressed,isNull);
    expect(writes(),isEmpty);
    await finish(tester);
  });

  testWidgets('old month response cannot replace the selected month or preserve selected dates',(tester) async {
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    final delayed=Completer<Map<int,Set<String>>>();var reads=0;
    repository.onMarks=(worker,month){reads++;return reads==1?delayed.future:Future.value({8:{'leave'}});};
    final next=find.byTooltip('一括カレンダーの次の月');
    await see(tester,next,up:true);await tester.tap(next);await tester.pump();
    expect(tester.widget<FilterChip>(day(3)).selected,false);
    expect(tester.widget<FilterChip>(day(3)).onSelected,isNull);
    await tester.tap(next);await tester.pumpAndSettle();
    await see(tester,day(8));expect(find.text('●有1/1'),findsOneWidget);
    delayed.complete({3:{'work'}});await tester.pumpAndSettle();
    expect(find.text('●出1/1'),findsNothing);
    expect(find.text('●有1/1'),findsOneWidget);
    expect(writes(),isEmpty);await finish(tester);
  });

  testWidgets('old employee selection response cannot replace a newer selected group',(tester) async {
    final delayed=Completer<Map<int,Set<String>>>();var workerReads=0;
    repository.onMarks=(worker,month){
      if(worker==fixture.worker&&++workerReads==1)return delayed.future;
      return Future.value(worker==fixture.actor?{8:{'work'}}:<int,Set<String>>{});
    };
    await mount(tester);await selectWorker(tester,'検証社員');
    await selectWorker(tester,'別社員');await tester.pumpAndSettle();await see(tester,day(8));
    expect(find.text('●出1/2'),findsOneWidget);
    delayed.complete({2:{'leave'}});await tester.pumpAndSettle();
    expect(find.text('●有1/1'),findsNothing);expect(find.text('●有1/2'),findsNothing);
    expect(tester.widget<FilterChip>(day(8)).selected,false);
    expect(writes(),isEmpty);await finish(tester);
  });

  testWidgets('confirmed deletion preserves the existing worker-date crossproduct',(tester) async {
    await mount(tester);await selectWorker(tester,'全員選択');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
    expect(find.textContaining('出勤印のない人も'),findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton,'一括削除'));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
    await tester.pumpAndSettle();
    final sent=writes().single;
    expect(sent['p_action'],'delete');
    final items=sent['p_items'] as List;
    expect(items,hasLength(2));
    expect(items.map((row)=>row['worker_id']).toSet(),{fixture.worker,fixture.actor});
    expect(items.map((row)=>row['date']).toSet(),hasLength(1));
    expect(repository.markReads.length,greaterThan(2));
    await finish(tester);
  });

  testWidgets('selection changed while confirmation is open prevents deletion',(tester) async {
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    final change=tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile,'検証社員')).onChanged!;
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
    change(false);await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
    expect(writes(),isEmpty);
    await finish(tester);
  });

  testWidgets('failed fresh pre-delete read prevents write despite an earlier known mark',(tester) async {
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
    repository.onMarks=(worker,month) async => throw StateError('synthetic failed preflight');
    await tester.tap(find.widgetWithText(FilledButton,'一括削除'));await tester.pumpAndSettle();
    expect(find.text('勤務日の目印を確認できないため、一括削除していません。'),findsOneWidget);
    await see(tester,deleteButton());
    expect(writes(),isEmpty);expect(tester.widget<OutlinedButton>(deleteButton()).onPressed,isNull);
    await finish(tester);
  });

  testWidgets('backgrounding during deletion confirmation invalidates selected dates and prevents write',(tester) async {
    await mount(tester);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      expect(find.textContaining('出勤印のない人も'),findsNothing);
      expect(writes(),isEmpty);
    } finally {
      await finish(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  });

  for(final boundary in ['actor','company','permission']) {
    testWidgets('parent $boundary boundary removes owned deletion modal without writing or popping parent',(tester) async {
      final visible=ValueNotifier(true);addTearDown(visible.dispose);
      await mount(tester,scopeVisible:visible);await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
      await see(tester,day(3));await tester.tap(day(3));await tester.pump();
      await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsOneWidget);
      visible.value=false;await tester.pumpAndSettle();
      expect(find.byType(AlertDialog),findsNothing);
      expect(find.textContaining('出勤印のない人も'),findsNothing);
      expect(find.text('検証社員'),findsNothing);
      expect(find.text('親の認証境界'),findsOneWidget);
      expect(writes(),isEmpty);expect(tester.takeException(),isNull);
      await finish(tester);
    });
  }

  testWidgets('OS back cancels owned confirmation before closing the parent page',(tester) async {
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(
        builder:(_)=>AttendanceManagementPage(repository:repository))),child:const Text('親画面から開く'))))));
    await tester.tap(find.text('親画面から開く'));await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab,'一括'));await tester.pumpAndSettle();
    await selectWorker(tester,'検証社員');await tester.pumpAndSettle();
    await see(tester,day(3));await tester.tap(day(3));await tester.pump();
    await see(tester,deleteButton());await tester.tap(deleteButton());await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();await tester.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
    expect(find.byType(AttendanceManagementPage),findsOneWidget);
    await tester.binding.handlePopRoute();await tester.pumpAndSettle();
    expect(find.byType(AttendanceManagementPage),findsNothing);
    expect(find.text('親画面から開く'),findsOneWidget);
    expect(writes(),isEmpty);
    await finish(tester);
  });
}
