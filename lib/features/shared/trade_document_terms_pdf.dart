import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/trade_document_terms_snapshot.dart';

/// Only an explicit supported snapshot gets the second page. Legacy stays legacy.
class TradeDocumentTermsPdf {
 const TradeDocumentTermsPdf._();
 static void append(pw.Document document,Map<String,dynamic> payload,
  {required pw.Font regularFont,required pw.Font boldFont}) {
  if(!payload.containsKey('contract_terms'))return;
  final terms=TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
  final articles=terms.articles,width=PdfPageFormat.a4.width-68,height=PdfPageFormat.a4.height-68;
  final lines=<pw.Widget>[];
  // Adopted source back page: one full-width column, 6.5pt body, 8.14pt leading.
  void paragraph(String value,{bool heading=false}){
   lines.add(pw.Text(value,tightBounds:true,style:pw.TextStyle(font:heading?boldFont:regularFont,fontSize:6.5,lineSpacing:1.64)));
   lines.add(pw.SizedBox(height:1.64));
  }
  for(var index=0;index<articles.length;index++){
   paragraph('（${articles[index].$1}）',heading:true);
   for(var part=0;part<articles[index].$2.length;part++){
    paragraph(part==0?'第${index+1}条　${articles[index].$2[part]}':articles[index].$2[part]);
   }
  }
  document.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(34),build:(_)=>pw.Stack(children:[
   pw.Positioned(left:0,top:0,child:pw.SizedBox(width:width,height:18,child:pw.Text(TradeDocumentTermsSnapshot.title,tightBounds:true,style:pw.TextStyle(font:boldFont,fontSize:12)))),
   pw.Positioned(left:0,top:21.5,child:pw.SizedBox(width:width,height:height-21.5,child:pw.Column(mainAxisSize:pw.MainAxisSize.min,crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:lines))),
  ])));
 }
}
