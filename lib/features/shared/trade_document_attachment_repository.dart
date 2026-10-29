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
  Future<Object?> _call(String action,Map<String,dynamic> params)async{
    final scope=_session??TradeDocumentFormSession(_client);
    try{return await scope.rpc(action,params);}finally{if(_session==null)scope.dispose();}
  }
  Future<Map<String,dynamic>> loadWorkspace({required String subjectKind,
      required String subjectId, required String sourceRevision}) async {
    final raw = await _call('trade_document_attachment_workspace', {
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision});
    if (raw is! Map) throw StateError('別添書類を確認できません。');
    return Map<String,dynamic>.from(raw);
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
    final raw=await _call('save_trade_document_attachment',{
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision,
      'p_expected_version':expectedVersion,'p_payload':payload});
    if(raw is! Map) throw StateError('別添書類を保存できません。');
    return TradeDocumentAttachment.fromJson(Map<String,dynamic>.from(raw));
  }
}
