import '../../domain/company_seal_snapshot.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import '../../domain/partner_company_bank_account.dart';

/// Explicitly saved monthly appendix. No legacy document opts in implicitly.
class TradeDocumentAttachment {
  const TradeDocumentAttachment({required this.version, required this.payload});
  final int version;
  final Map<String, dynamic> payload;
  factory TradeDocumentAttachment.fromJson(Map<String, dynamic> json) {
    final value = json['payload'];
    if (json['version'] is! int || (json['version'] as int) < 1 || value is! Map) {
      throw StateError('保存された別添書類を確認できません。');
    }
    final payload = Map<String, dynamic>.from(value);
    if (payload['version'] != 1 || !{'order','acceptance'}.contains(payload['kind']) ||
        !RegExp(r'^\d{4}-\d{2}$').hasMatch(payload['month']?.toString() ?? '')) {
      throw StateError('別添書類の対象月・種類を確認できません。');
    }
    for (final key in ['issuer','counterparty']) {
      if (payload[key] is! Map || (payload[key]['name']?.toString().trim() ?? '').isEmpty) {
        throw StateError('別添書類の会社を確認できません。');
      }
    }
    if(payload['kind']=='order' && payload['counterparty_bank']!=null) {
      PartnerCompanyBankAccount.fromJson(payload['counterparty_bank']);
    }
    if(payload.containsKey('contract_terms')) TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
    CompanySealSnapshot.fromJson(payload['company_seal_snapshot']);
    return TradeDocumentAttachment(version:json['version'] as int, payload:Map.unmodifiable(payload));
  }
}
