import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_approval_contract.dart';
import 'package:sk_works/features/sites/site_order_workflow.dart';

const scope=SiteOrderScope(actorId:'actor',companyId:'own',sessionId:'sid',siteId:'accepted-site');
SiteOrderArtifact artifact({required bool acceptance,int price=32000,String? counterparty})=>SiteOrderArtifact(
  id:acceptance?'acceptance':'incoming-order',companyId:acceptance?'own':'original-sender',
  siteId:acceptance?'accepted-site':'original-site',revision:2,
  pdfSha256:(acceptance?'b':'a')*64,title:'現場A',startsOn:'2026-10-01',endsOn:'2026-10-31',
  sealVersionId:acceptance?'own-registered-seal':'sender-registered-seal',
  kind:acceptance?SiteOrderArtifactKind.acceptance:SiteOrderArtifactKind.order,
  counterpartyCompanyId:counterparty??(acceptance?'original-sender':'own'),
  counterpartyName:acceptance?'取引会社':'自社',counterpartyTradeCompanyId:'registered-trade',
  counterpartyConnectionFingerprint:'c'*64,
  prices:[SiteOrderPrice(item:'とび工',unitPriceYen:price,unit:'人日')]);
SiteOrderApprovalIntent intent({int acceptancePrice=32000,String? hash})=>SiteOrderApprovalIntent(
  requestId:'request',scope:scope,packageId:'package',packageRevision:2,
  incomingOrder:artifact(acceptance:false),acceptance:artifact(acceptance:true,price:acceptancePrice),
  acceptedOrderPdfSha256:hash??'a'*64);
SiteOrderApprovalReceipt receipt({String? outbox,String? recipient})=>SiteOrderApprovalReceipt(
  requestId:'request',actorId:'actor',sessionId:'sid',companyId:'own',packageId:'package',
  packageRevision:2,incomingOrderPdfSha256:'a'*64,acceptedSiteId:'accepted-site',
  acceptanceArtifactId:'acceptance',acceptanceArtifactRevision:2,acceptancePdfSha256:'b'*64,
  acceptanceRecipientCompanyId:recipient??'original-sender',acceptanceOutboxId:outbox??'outbox');
String uuid(int n)=>'00000000-0000-4000-8000-${n.toString().padLeft(12,'0')}';
Map<String,Object> notice()=>{'notification_id':uuid(1),'event_id':uuid(2),
  'company_id':uuid(3),'package_id':uuid(4),'package_revision':2,
  'kind':'approval_required','contract_version':1};
Map<String,Object> capability()=>{
  'site_order_documents':true,'can_view_archive':true,'can_manage_orders':true,
  for(final key in ['archive','documents','artifact','approval','delivery','recovery','notification'])
    'site_order_${key}_contract_version':1};

void main(){
  test('approval fixes reply recipient to original sender and requires sealed acceptance receipt',(){
    final i=intent();
    expect(i.acceptanceRecipientCompanyId,'original-sender');
    expect(receipt().matches(i),isTrue);
    expect(receipt(outbox:'').matches(i),isFalse);
    expect(receipt(recipient:'other-company').matches(i),isFalse);
  });
  test('approval never reapplies fresh defaults or changes incoming unit prices',(){
    expect(()=>intent(acceptancePrice:999),throwsStateError);
    expect(()=>intent(hash:'c'*64),throwsStateError);
    expect(()=>SiteOrderApprovalIntent(requestId:'request',scope:scope,packageId:'package',
      packageRevision:2,incomingOrder:artifact(acceptance:false),
      acceptance:artifact(acceptance:false),acceptedOrderPdfSha256:'a'*64),throwsStateError);
    expect(()=>SiteOrderApprovalIntent(requestId:'request',scope:scope,packageId:'package',
      packageRevision:2,incomingOrder:artifact(acceptance:false,counterparty:'another-receiver'),
      acceptance:artifact(acceptance:true),acceptedOrderPdfSha256:'a'*64),throwsStateError);
    expect(()=>SiteOrderApprovalIntent(requestId:'request',scope:scope,packageId:'package',
      packageRevision:2,incomingOrder:artifact(acceptance:false),
      acceptance:artifact(acceptance:true,counterparty:'wrong-sender'),acceptedOrderPdfSha256:'a'*64),throwsStateError);
  });
  test('notice resolves exact company/package/revision from strict private envelope',(){
    final target=SiteOrderNoticeTarget.fromJson(notice(),expectedCompanyId:uuid(3));
    expect(target.packageId,uuid(4));expect(target.packageRevision,2);
    expect(target.kind,SiteOrderNoticeKind.approvalRequired);
    expect(()=>SiteOrderNoticeTarget.fromJson(notice(),expectedCompanyId:uuid(9)),throwsFormatException);
  });
  test('notice does not accept price/url payload or malformed link',(){
    expect(()=>SiteOrderNoticeTarget.fromJson({...notice(),'pdf_url':'secret'},expectedCompanyId:uuid(3)),throwsFormatException);
    expect(()=>SiteOrderNoticeTarget.fromJson({...notice(),'notification_id':'name'},expectedCompanyId:uuid(3)),throwsFormatException);
    expect(()=>SiteOrderNoticeTarget.fromJson({...notice(),'kind':'unknown'},expectedCompanyId:uuid(3)),throwsFormatException);
    expect(()=>SiteOrderNoticeTarget.fromJson({...notice(),'contract_version':1.0},expectedCompanyId:uuid(3)),throwsFormatException);
  });
  test('absent, off and incomplete master deployment do not authorize mutation',(){
    expect(SiteOrderAvailability.fromJson(null).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson({}).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson({...capability(),'site_order_documents':false}).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson({...capability(),'site_order_artifact_contract_version':0}).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson({...capability(),'site_order_notification_contract_version':'1'}).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson({...capability(),'can_manage_orders':false}).canMutate,isFalse);
    expect(SiteOrderAvailability.fromJson(capability()).canMutate,isTrue);
  });
  test('master OFF preserves protected historical archive viewing',(){
    final flags=SiteOrderAvailability.fromJson({...capability(),'site_order_documents':false});
    expect(flags.canMutate,isFalse);expect(flags.canViewArchive,isTrue);
    expect(SiteOrderAvailability.fromJson({...capability(),'can_view_archive':false}).canViewArchive,isFalse);
  });
}
