import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'trade_document_terms_source.dart';

/// Content-addressed immutable source reference, included in the approved body.
/// New versions must retain every historical registry entry and exact JSON file.
class TradeDocumentTermsSnapshot {
 const TradeDocumentTermsSnapshot._();
 static const sourceSha256='3acf9090f2c027840bba43351f4d9e173759baa8b7c0340c05db9e28731f0d1f';
 static const title='[ 工事請負契約条項 ]';
 static const reference=<String,dynamic>{'schema':1,'version':1,'title':title,'source_sha256':sourceSha256,'renderer_contract':'sko-original-form-20261029-v1','design_sha256':'942bad918b696b4c2c527dbf2fca9d050e4fb38a3674cff115eb0755793b8a18'};
 static TradeDocumentTermsSnapshot fromJson(Object? raw) {
  if(raw is! Map || raw['schema'] is! int || raw['version'] is! int || raw.length!=reference.length || !reference.entries.every((entry)=>raw[entry.key]==entry.value) ||
      sha256.convert(utf8.encode(tradeDocumentTermsV1Json)).toString()!=sourceSha256) {
   throw const FormatException('契約条項の確定版・本文ハッシュを確認できません。');
  }
  return const TradeDocumentTermsSnapshot._();
 }
 static Map<String,dynamic> initialize(Map<String,dynamic> payload) {
  final result=Map<String,dynamic>.from(payload);
  if(result.containsKey('contract_terms')) {fromJson(result['contract_terms']);}
  else {result['contract_terms']=Map<String,dynamic>.from(reference);}
  return result;
 }
 List<(String,List<String>)> get articles {
  final raw=jsonDecode(tradeDocumentTermsV1Json) as List;
  return List.unmodifiable(raw.map((row)=>(row[0] as String,List<String>.unmodifiable((row[1] as List).cast<String>()))));
 }
}
