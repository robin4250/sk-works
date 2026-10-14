import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_actor_boundary.dart';
void main(){
 test('async output lease remains revoked after A to B to A',(){
  final changes=StreamController<String?>.broadcast(sync:true);
  final lease=TradeDocumentActorLease(initialActor:'actor-a',actorChanges:changes.stream);
  expect(lease.verify,returnsNormally);changes.add('actor-b');expect(lease.verify,throwsStateError);
  changes.add('actor-a');expect(lease.verify,throwsStateError);lease.dispose();changes.close();
 });
 test('async output lease fails closed on auth-stream error',(){
  final changes=StreamController<String?>.broadcast(sync:true);
  final lease=TradeDocumentActorLease(initialActor:'actor-a',actorChanges:changes.stream);
  changes.addError(StateError('stream failed'));expect(lease.verify,throwsStateError);lease.dispose();changes.close();
 });
 testWidgets('account swap removes a saved contract preview and does not restore it', (tester)async{
  final changes=StreamController<String?>.broadcast(sync:true);
  await tester.pumpWidget(MaterialApp(home:TradeDocumentActorBoundary(initialActor:'actor-a',actorChanges:changes.stream,
   child:const Scaffold(body:Text('保存した月次契約')))));
  expect(find.text('保存した月次契約'),findsOneWidget);changes.add(null);await tester.pump();
  expect(find.text('保存した月次契約'),findsNothing);changes.add('actor-a');await tester.pump();
  expect(find.text('保存した月次契約'),findsNothing);await tester.pumpWidget(const SizedBox());await changes.close();
 });
}
