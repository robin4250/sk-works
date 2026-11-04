import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';
const actor='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';
Map<String,Object?> row(String uid,{String status='pending',bool allowed=true})=>{'approver_user_id':uid,'status':status,'can_current_user_approve':allowed};
void main(){
 test('exact current reviewer with explicit permission remains pending after reading',(){
  expect(invoicePendingNotificationState(currentUserId:actor,value:[row(actor)]),NotificationBusinessState.pending);
 });
 test('other reviewer or missing current permission cannot create a task',(){
  for(final rows in [[row(other,allowed:false)],[row(actor,allowed:false)]]){
   expect(invoicePendingNotificationState(currentUserId:actor,value:rows),NotificationBusinessState.unknown);
  }
 });
 test('approved rows cannot substitute for invoice finalization',(){
  expect(invoicePendingNotificationState(currentUserId:actor,value:[row(actor,status:'approved',allowed:false)]),NotificationBusinessState.unknown);
 });
 test('missing duplicate malformed and contradictory responses stay unknown',(){
  for(final value in [null,[],[row(actor),row(actor)],[row(other)],[row(actor,status:'approved')],[{'approver_user_id':actor,'status':'pending'}]]){
   expect(invoicePendingNotificationState(currentUserId:actor,value:value),NotificationBusinessState.unknown);
  }
 });
}
