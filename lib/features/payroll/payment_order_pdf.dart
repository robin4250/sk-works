import 'payment_order_layout.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/company_seal_snapshot.dart';
import '../shared/company_seal_pdf.dart';
import '../shared/trade_document_attachment.dart';

class PaymentOrderPdf {
 const PaymentOrderPdf._();
 static Future<void> append(pw.Document document,TradeDocumentAttachment attachment,
   {required pw.Font regularFont,required pw.Font boldFont})async{
  final p=attachment.payload;
  if(p['kind']!='order')throw StateError('注文書の保存内容を確認できません。');
  final issuer=Map<String,dynamic>.from(p['issuer'] as Map);
  final counter=Map<String,dynamic>.from(p['counterparty'] as Map);
  final seal=CompanySealSnapshot.fromJson(p['company_seal_snapshot']);
  final sealOn=p['company_seal_enabled']==true;
  final font=sealOn?await CompanySealPdf.loadStyleFont(seal.style):regularFont;
  final compact=paymentOrderUsesCompactLayout(p);
  final size=compact?8.0:10.0;
  pw.Widget text(String value,{bool bold=false})=>pw.Text(value,
   style:pw.TextStyle(font:bold?boldFont:regularFont,fontSize:size,lineSpacing:compact?0:2));
  pw.Widget field(String name,Object? value)=>pw.Padding(padding:pw.EdgeInsets.only(bottom:compact?3:7),child:text('$name：${value??''}'));
  pw.Widget party(String title,Map<String,dynamic> value,{bool own=false})=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
   text(title,bold:true),pw.SizedBox(height:5),field('社名','${value['name']}${own?'':'　御中'}'),field('住所',value['address']),
   field('法人番号',value['corporate_number']),pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
    pw.Expanded(child:field('代表者名',value['representative_name'])),
    if(own&&sealOn)CompanySealPdf.build(seal.registeredName(issuer['name'].toString()),font:font,companyId:seal.companyId,uploadedPng:seal.uploadedPng,
      fallbackFont:regularFont,style:seal.style,size:compact?40:48),]),]);
  document.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(36),build:(_)=>pw.Column(
   crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
    pw.Center(child:pw.Text('注文書',style:pw.TextStyle(font:boldFont,fontSize:compact?18:22,letterSpacing:5))),
    pw.SizedBox(height:compact?6:8),pw.Center(child:text('${p['month']} 月分')),pw.SizedBox(height:compact?8:14),
    text(p['intro_text']?.toString()??''),pw.SizedBox(height:compact?8:14),
    field('1. 工事名',p['work_name']),field('2. 工事場所',p['work_address']),
    field('3. 工期','${p['period_start']} から ${p['period_end']} まで'),
    field('4. 請負代金','金 ${_money(p['total_amount_yen'])}円（うち消費税等 金${_money(p['tax_amount_yen'])}円）'),
    field('5. 支払条件',p['payment_conditions']),field('6. その他特記事項',p['notes']),
    pw.SizedBox(height:compact?6:12),pw.Align(alignment:pw.Alignment.centerRight,child:text(p['issue_date'].toString())),
    pw.SizedBox(height:compact?8:14),
    if(compact)pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Expanded(child:party('（甲・発注者）',issuer,own:true)),pw.SizedBox(width:16),
      pw.Expanded(child:party('（乙・受注者）',counter)),
    ])else ...[party('（甲・発注者）',issuer,own:true),pw.SizedBox(height:12),party('（乙・受注者）',counter)],
  ])));
 }
 static String _money(Object? value){
  if(value is! int||value<0)throw StateError('請負代金・消費税額を確認できません。');
  return value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>',');
 }
}

