import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_attachment.dart';
import 'trade_document_date_defaults.dart';

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
  /// Generate the second page from the authorized source; no extra save action.
  Future<TradeDocumentAttachment> loadForPdf({required String subjectKind,
      required String subjectId, required String sourceRevision}) async {
    final actor = _actor();
    final raw = await loadWorkspace(subjectKind: subjectKind,
        subjectId: subjectId, sourceRevision: sourceRevision);
    if (raw['source_blocked'] == true) {
      throw StateError('元帳票の計算条件を確認してください。');
    }
    final saved = raw['attachment'];
    if (saved is Map && raw['source_changed'] != true) {
      return TradeDocumentAttachment.fromJson(Map<String, dynamic>.from(saved));
    }
    final payload = Map<String, dynamic>.from(raw['defaults'] as Map);
    payload.addAll(tradeDocumentDateDefaults(payload['month'].toString()));
    payload['notes'] = '';
    if (subjectKind == 'payment_certificate') {
      final settings = await _client.rpc('invoice_document_settings');
      if (settings is! Map) throw StateError('請求書の件名を取得できません。');
      _sameActor(actor);
      payload['work_name'] = settings['invoice_subject']?.toString() ?? '';
      payload['work_address'] = '';
      payload['intro_text'] = '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。';
      payload['payment_conditions'] = tradeDocumentDefaultPaymentConditions(payload['month'].toString());
      payload['notes'] = '・本工事は建設業許可を必要としない軽微な工事である。\n・乙は、工事中の事故等について一切の責任を負う。';
    } else {
      payload['issue_date'] = DateTime.now().toUtc().add(const Duration(hours: 9))
          .toIso8601String().substring(0, 10);
      payload['acceptance_text'] = '乙は、貴殿から受領した'
          '${tradeDocumentJapaneseDate(payload['order_date'].toString())}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。';
    }
    _sameActor(actor);
    return TradeDocumentAttachment.fromJson({'version': 1, 'payload': payload});
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
