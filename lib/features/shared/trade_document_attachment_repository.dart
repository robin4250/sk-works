import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_attachment.dart';
import 'trade_document_form_session.dart';

class TradeDocumentAttachmentRepository {
  TradeDocumentAttachmentRepository(this._client,{TradeDocumentFormSession? session}):_session=session{
    if(session!=null&&!session.belongsTo(_client))throw ArgumentError('Session/client mismatch');
  }
  final SupabaseClient _client;
  final TradeDocumentFormSession? _session;
  static TradeDocumentAttachmentRepository? maybeCreate({TradeDocumentFormSession? session}) =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
        ? TradeDocumentAttachmentRepository(SupabaseBackend.client,session:session) : null;
  bool isBoundTo(TradeDocumentFormSession session)=>identical(_session,session);
  Future<T> _within<T>(Future<T> Function(TradeDocumentFormSession) action)async{
    final scope=_session??TradeDocumentFormSession(_client);
    try{return await action(scope);}finally{if(_session==null)scope.dispose();}
  }
  Future<Map<String,dynamic>> loadWorkspace({required String subjectKind,
      required String subjectId, required String sourceRevision}) async {
    return _within((scope)async{
    final raw = await scope.rpc('trade_document_attachment_workspace', {
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision});
    if (raw is! Map) throw StateError('別添書類を確認できません。');
    final result=Map<String,dynamic>.from(raw),attachment=raw['attachment'];
    if(subjectKind=='payment_certificate'&&attachment is Map&&attachment['payload'] is Map&&attachment['payload']['counterparty_bank']!=null){
      final company=raw['company_id'];if(company is! String)throw StateError('保存した振込先の会社を確認できません。');
      final parent=await scope.readPaymentParent(id:subjectId,companyId:company);
      if(parent is! Map||parent['id']!=subjectId||parent['company_id']!=company||parent['revision']?.toString()!=raw['source_revision']?.toString())throw StateError('元の会社・受注者・書類版を確認できません。');
      result['canonical_parent_binding']={'parent_id':parent['id'],'company_id':parent['company_id'],'partner_company_id':parent['partner_company_id']};
    }
    return result;});
  }
  Future<TradeDocumentAttachment?> load({required String subjectKind,
      required String subjectId,required String sourceRevision}) async {
    final raw = await loadWorkspace(subjectKind:subjectKind,subjectId:subjectId,sourceRevision:sourceRevision);
    if(raw['source_changed']==true)throw StateError('元帳票が更新されています。注文書・注文請書を開き、内容を確認して保存し直してください。');
    final value=raw['attachment'];
    return value==null?null:TradeDocumentAttachment.fromJson(Map<String,dynamic>.from(value as Map));
  }
  Future<TradeDocumentAttachment> save({required String subjectKind,
      required String subjectId,required String sourceRevision,required int expectedVersion,
      required Map<String,dynamic> payload}) async {
    return _within((scope)async{
    final raw=await scope.rpc('save_trade_document_attachment',{
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision,
      'p_expected_version':expectedVersion,'p_payload':payload});
    if(raw is! Map) throw StateError('別添書類を保存できません。');
    return TradeDocumentAttachment.fromJson(Map<String,dynamic>.from(raw));});
  }
}
