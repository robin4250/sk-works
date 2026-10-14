import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_attachment.dart';

class TradeDocumentAttachmentRepository {
  TradeDocumentAttachmentRepository(this._client);
  final SupabaseClient _client;
  static TradeDocumentAttachmentRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
        ? TradeDocumentAttachmentRepository(SupabaseBackend.client) : null;
  String _actor() => _client.auth.currentUser?.id ?? (throw StateError('ログインが必要です。'));
  void _sameActor(String actor) {
    if (_client.auth.currentUser?.id != actor) throw StateError('ログイン情報が変わりました。開き直してください。');
  }
  Future<Map<String,dynamic>> loadWorkspace({required String subjectKind,
      required String subjectId, required String sourceRevision}) async {
    final actor = _actor();
    final raw = await _client.rpc('trade_document_attachment_workspace', params:{
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision});
    _sameActor(actor);
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
    final actor=_actor();
    final raw=await _client.rpc('save_trade_document_attachment',params:{
      'p_kind':subjectKind,'p_subject':subjectId,'p_source_revision':sourceRevision,
      'p_expected_version':expectedVersion,'p_payload':payload});
    _sameActor(actor);
    if(raw is! Map) throw StateError('別添書類を保存できません。');
    return TradeDocumentAttachment.fromJson(Map<String,dynamic>.from(raw));
  }
}
