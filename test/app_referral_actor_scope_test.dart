import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/referrals/app_referral_actor_scope.dart';
import 'package:sk_works/features/referrals/app_referral_composer.dart';
import 'package:sk_works/features/referrals/app_referral_page.dart';
import 'package:sk_works/features/referrals/app_referral_personal_entry.dart';
import 'package:sk_works/features/referrals/app_referral_master_entry.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';

class _Repository implements AppReferralRepository {
  String actor = 'self';
  final changes = StreamController<String?>.broadcast(sync: true);
  Completer<Map<String,dynamic>>? pending;
  int loads=0;
  final data=<String,dynamic>{'enabled':true,'can_invite':true,'distribution_url_ready':false,
    'invitations':<Object>[{'recipient_name':'PRIVATE-HISTORY','recipient_phone':'09012345678','created_at':'2026-10-01T00:00:00Z'}]};
  @override
  String? get currentActorId=>actor;
  @override
  Stream<String?> watchActorChanges()=>changes.stream;
  @override
  Future<Map<String,dynamic>> load({bool master=false}) async {loads++;return pending==null?data:await pending!.future;}
  void aba(){actor='other';changes.add(actor);actor='self';changes.add(actor);}
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
void main(){
  for(final failure in [false,true]){
    testWidgets('pending page ${failure?'failure':'success'} cannot restore history after ABA',(tester) async {
      final repo=_Repository()..pending=Completer<Map<String,dynamic>>();addTearDown(repo.changes.close);
      await tester.pumpWidget(MaterialApp(home:AppReferralPage(repository:repo)));
      await tester.pump();repo.aba();await tester.pumpAndSettle();
      if(failure){repo.pending!.completeError(StateError('obsolete-referral'));}else{repo.pending!.complete(repo.data);}
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE-HISTORY'),findsNothing);
      expect(find.textContaining('画面を開き直してください'),findsOneWidget);
      await tester.tap(find.text('再読み込み'));await tester.pumpAndSettle();expect(repo.loads,1);
    });
  }
  for(final master in [false,true]){
    testWidgets('${master?'master':'personal'} entry clears permission after ABA',(tester) async {
      final repo=_Repository();addTearDown(repo.changes.close);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:master?AppReferralMasterEntry(repository:repo):AppReferralPersonalEntry(repository:repo))));
      await tester.pumpAndSettle();repo.aba();await tester.pumpAndSettle();
      expect(find.textContaining('画面を開き直してください'),findsOneWidget);
      expect(find.byType(AppReferralPage),findsNothing);
    });
  }
  testWidgets('open page hides loaded history after stream failure',(tester) async {
    final repo=_Repository();addTearDown(repo.changes.close);
    await tester.pumpWidget(MaterialApp(home:AppReferralPage(repository:repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE-HISTORY'),findsOneWidget);
    // An error invalidates the page even if the user id has not changed.
    repo.changes.addError(StateError('synthetic stream failure'));await tester.pumpAndSettle();
    expect(find.textContaining('PRIVATE-HISTORY'),findsNothing);
    expect(find.textContaining('画面を開き直してください'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  for(final stage in ['prepare','open']){
    test('composer $stage ABA cannot open or record for the old scope',() async {
      final repo=_Repository();var invalidations=0,opened=0,recorded=0;
      final scope=AppReferralActorScope(repo,onInvalidated:()=>invalidations++);
      final composer=AppReferralComposer(actorId:()=>scope.check()?scope.actor:null,
        prepare:(n,p,f)async{if(stage=='prepare')repo.aba();return {'id':'invitation','phone':p,'message':'synthetic link'};},
        openComposer:(uri)async{opened++;if(stage=='open')repo.aba();return true;},
        recordOpened:(id)async{recorded++;});
      expect(await composer.send(name:'Synthetic',phone:'09012345678',friendInvite:false),AppReferralComposeOutcome.actorChanged);
      expect(opened,stage=='prepare'?0:1);expect(recorded,0);expect(invalidations,1);
      expect(scope.valid,isFalse);scope.dispose();await repo.changes.close();
    });
  }
  test('disposed scope prevents a delayed preparation from opening composer',() async {
    final repo=_Repository();final scope=AppReferralActorScope(repo,onInvalidated:(){});
    final prepared=Completer<Map<String,dynamic>>();var opened=0;
    final composer=AppReferralComposer(actorId:()=>scope.check()?scope.actor:null,
      prepare:(n,p,f)=>prepared.future,openComposer:(uri)async{opened++;return true;},recordOpened:(id)async{});
    final result=composer.send(name:'Synthetic',phone:'09012345678',friendInvite:false);
    scope.dispose();prepared.complete({'id':'invitation','phone':'09012345678','message':'synthetic'});
    expect(await result,AppReferralComposeOutcome.actorChanged);expect(opened,0);await repo.changes.close();
  });
}
