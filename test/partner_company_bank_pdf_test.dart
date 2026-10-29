import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/payroll/payment_order_pdf.dart';

Map<String,dynamic> partnerOrder({bool withBank=true,bool long=false})=>{
 'version':1,'kind':'order','month':'2026-10','issue_date':'2026-09-15','period_start':'2026-10-01','period_end':'2026-10-31',
 'intro_text':long?'発注条件'*100:'工事を発注します。','work_name':long?'工事'*120:'内装工事','work_address':long?'住所'*120:'東京都1-2-3',
 'total_amount_yen':110000,'tax_amount_yen':10000,'payment_conditions':long?'完了確認'*100:'完了後に支払う。','notes':long?'備考'*300:'既存条件',
 'issuer':{'name':'株式会社発注','address':'東京都','corporate_number':'1234567890123','representative_name':'甲代表'},
 'counterparty':{'name':'株式会社受注','address':'神奈川県','corporate_number':'9876543210987','representative_name':'乙代表'},
 'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'株式会社発注'},
 if(withBank)'counterparty_bank':{'schema':1,'company_id':'10000000-0000-4000-8000-000000000001','partner_company_id':'10000000-0000-4000-8000-000000000002','bank_version':2,
  'bank_name':long?'銀'*100:'保存済検証銀行','branch_name':long?'支'*100:'保存済本店','account_type':'普通','account_number':'0000123','account_holder':long?'名'*120:'カブシキガイシャジュチュウ'},
};
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 test('actual new order PDF renders only supplied frozen supplier bank; legacy payload remains bank-free',() async {
  final font=await CompanySealPdf.loadFont();final output=Platform.environment['PARTNER_BANK_PDF_OUTPUT_DIR'];
  for(final variant in ['bank','bank-long','legacy']){
   final doc=pw.Document();final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':partnerOrder(withBank:variant!='legacy',long:variant=='bank-long')});
   await PaymentOrderPdf.append(doc,attachment,regularFont:font,boldFont:font);final bytes=await doc.save();expect(bytes.length,greaterThan(1000));
   if(output!=null){Directory(output).createSync(recursive:true);File('$output/$variant.pdf').writeAsBytesSync(bytes);}
  }
 });
}
