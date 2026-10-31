import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/people_cloud_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/employee_personnel_detail_page.dart';
import 'package:sk_works/features/people/employee_retirement_repository.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

const company = '60000000-0000-0000-0000-000000000010';
const otherCompany = '60000000-0000-0000-0000-000000000011';
const worker = '60000000-0000-0000-0000-000000000020';
const workerName = 'Retirement fixture employee';

class RosterFixture extends PeopleCloudRepository {
  RosterFixture(this.wire) : super.forTesting(wire.client);
  final fixture.Wire wire;
  bool employed = true;
  String role = 'admin';
  int reads = 0;
  Completer<List<Map<String,dynamic>>>? pendingRoster;
  Map<String,dynamic> get row => {'id':worker,'kind':'employee','name':workerName,'active':employed};
  @override Future<({String companyId, String role})> membership({String? companyId}) async =>
      (companyId:companyId ?? company, role:role);
  @override Future<String> companyName({String? companyId}) async => 'Fixture company';
  @override Future<bool> canManagePeople({String? companyId}) async => role == 'admin';
  @override Future<bool> canViewPeople({String? companyId}) async => true;
  @override Future<bool> canConfigurePersonnelApprovers({String? companyId}) async => false;
  @override Future<List<Map<String,dynamic>>> loadAll({String? expectedCompany}) async {
    reads++;
    final pending=pendingRoster;
    if(pending!=null) return pending.future;
    return [Map<String,dynamic>.from(row)];
  }
  @override Future<String?> portraitUrl(String workerId,{String? companyId}) async => null;
  @override PersonnelPrivacySession privacySession(String selectedCompany) => PersonnelPrivacySession(
    actor: actorId, company:selectedCompany, currentActor:()=>actorId,
    actorChanges:wire.client.auth.onAuthStateChange.map((event)=>event.session?.user.id),
    load:() async => PersonnelPrivacySnapshot(actor:actorId!,company:selectedCompany,
      role:role,canManage:role=='admin',records:[Map<String,dynamic>.from(row)]),
  );
}

void main() {
  late fixture.Wire wire;
  late RosterFixture repository;
  setUp(() async {
    wire = fixture.Wire();
    await wire.seed();
    repository = RosterFixture(wire);
    wire.respond = (request) async {
      if (request.url.path.endsWith('/company_members')) {
        return fixture.Wire.json([{'company_id':company,'role':repository.role}]);
      }
      if (request.url.path.endsWith('/rpc/employee_personnel_view')) {
        return fixture.Wire.json({'company_id':company,'records':[
          if(repository.employed) Map<String,dynamic>.from(repository.row),
        ]});
      }
      if (request.url.path.endsWith('/workers')) {
        if(request.method=='PATCH') repository.employed=false;
        return fixture.Wire.json([{'id':worker,'company_id':company,
          'status':repository.employed?'active':'inactive'}]);
      }
      throw StateError('Unexpected fixture endpoint ${request.url.path}');
    };
  });
  tearDown(() async { await wire.client.dispose(); });

  Future<void> openDetail(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home:PeopleCloudPage(
      companyId:company,repositoryOverride:repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(workerName));
    await tester.pumpAndSettle();
    expect(find.byType(EmployeePersonnelDetailPage),findsWidgets);
  }
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('confirmed retirement save then real detail return updates active and retired filters', (tester) async {
    await openDetail(tester);
    await tester.runAsync(()=>EmployeeRetirementRepository(wire.client).retire(
      companyId:company,workerId:worker,verifyContext:(){}));
    expect(repository.employed,false);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(workerName),findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip,'退職者'));
    await tester.pump();
    expect(find.text(workerName),findsOneWidget);
    expect(wire.calls.where((r)=>r.method=='PATCH'),hasLength(1));
    expect(wire.calls.any((r)=>r.method=='DELETE'),false);
    await close(tester);
  });

  testWidgets('cancelled detail return re-reads without any retirement write', (tester) async {
    await openDetail(tester);
    final initialReads=repository.reads;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.reads,greaterThan(initialReads));
    expect(find.text(workerName),findsOneWidget);
    expect(wire.calls.where((r)=>r.method!='GET'),isEmpty);
    await close(tester);
  });

  for(final boundary in ['actor','role','company','paused']) {
    testWidgets('delayed return roster never restores old rows after $boundary boundary', (tester) async {
      await openDetail(tester);
      final oldRow=Map<String,dynamic>.from(repository.row);
      final pending=Completer<List<Map<String,dynamic>>>();
      repository.pendingRoster=pending;
      final initialReads=repository.reads;
      await tester.pageBack();
      for(var frame=0; frame<10 && repository.reads==initialReads; frame++) {
        await tester.pump(const Duration(milliseconds:100));
      }
      await tester.pump();
      expect(repository.reads,greaterThan(initialReads));
      // The popped route can still paint during its exit animation even after
      // the parent's refresh dispatches. Wait for that real detail to unmount.
      for(var frame=0; frame<10 && find.byType(EmployeePersonnelDetailPage).evaluate().isNotEmpty; frame++) {
        await tester.pump(const Duration(milliseconds:100));
      }
      expect(find.byType(EmployeePersonnelDetailPage),findsNothing);
      expect(find.text(workerName),findsNothing);
      if(boundary=='actor') {
        await tester.runAsync(()=>wire.seed(uid:fixture.other));
      } else if(boundary=='role') {
        repository.role='viewer';
      } else if(boundary=='company') {
        await tester.pumpWidget(MaterialApp(home:PeopleCloudPage(
          companyId:otherCompany,repositoryOverride:repository)));
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      try {
        pending.complete([oldRow]);
        await tester.pumpAndSettle();
        expect(find.text(workerName),findsNothing);
        expect(wire.calls.where((r)=>r.method!='GET'),isEmpty);
      } finally {
        await close(tester);
        if(boundary=='paused') {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
      }
    });
  }
}
