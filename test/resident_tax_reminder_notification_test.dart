import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/payroll/resident_tax_reminder_repository.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_page.dart';
const company='00000000-0000-0000-0000-000000000100';
AppNotificationRecord notice(String id,int? year,{bool complete=false,bool read=false,String kind='resident_tax_reminder'})=>AppNotificationRecord(
 id:id,kind:kind,title:'住民税の切替準備',body:'通知書が届いたら確認',createdAt:DateTime(2026,5,1),read:read,
 actionKey:'payroll_settings',actionId:company,businessStatus:NotificationBusinessStatus(
 state:year==null?NotificationBusinessState.unknown:complete?NotificationBusinessState.completed:NotificationBusinessState.pending,
 targetDate:year==null?null:DateTime(year,6,1)));
void main(){
 test('read notification remains pending until annual source confirms',(){
  final item=mapAttentionNotification(notice('a',2026,read:true));expect(item.needsAction,true);expect(item.read,true);
 });
 test('completion removes pending count but retains unread history',(){
  final item=mapAttentionNotification(notice('a',2026,complete:true));
  final snapshot=AttentionCenterSnapshot([item],now:DateTime(2026,5,25));expect(snapshot.unresolvedCount,0);expect(snapshot.items,singleElement);
  expect(item.title,contains('更新確認済み'));expect(item.read,false);
 });
 test('company-year task groups phases but preserves different years',(){
  final a=mapAttentionNotification(notice('month',2026)),b=mapAttentionNotification(notice('week',2026));
  final next=mapAttentionNotification(notice('next',2027));expect(a.deduplicationKey,b.deduplicationKey);expect(a.deduplicationKey,isNot(next.deduplicationKey));
 });
 test('missing annual target never invents a year from message text',(){
  final a=mapAttentionNotification(notice('one',null)),b=mapAttentionNotification(notice('two',null));
  expect(a.needsAction,false);expect(a.deduplicationKey,isNot(b.deduplicationKey));
 });
 test('old individual payroll action remains information and generic route',(){
  final item=notice('a',null,kind:'payroll_setting_changed');expect(item.hasBusinessTarget,false);
  expect(notificationDestination(item),isA<SecondaryProtectedPage>());
 });
 test('resident kind cannot fall through into old individual route',(){expect(notificationDestination(notice('a',2026)),isNull);});
 test('verified company-year target opens annual page with company panel',(){
  final route=residentTaxReminderDestination(notice('a',2026),const ResidentTaxReminderTarget(companyId:company,fiscalYear:2026,complete:false)) as SecondaryProtectedPage;
  final page=route.child as ResidentTaxAnnualUpdatePage;expect(page.companyId,company);expect(page.fiscalYear,2026);expect(page.reminderPanel,isNotNull);
 });
 test('mismatched company cannot construct annual notification route',(){
  expect(()=>residentTaxReminderDestination(notice('a',2026),const ResidentTaxReminderTarget(companyId:'different',fiscalYear:2026,complete:false)),throwsFormatException);
 });
}
