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
  final articles=terms.articles;
  pw.Widget column(int start,int end)=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
   for(var index=start;index<end;index++)...[
    pw.Text('第${index+1}条　${articles[index].$1}',style:pw.TextStyle(font:boldFont,fontSize:7.2)),
    for(final paragraph in articles[index].$2)pw.Text(paragraph,style:pw.TextStyle(font:regularFont,fontSize:7,lineSpacing:0.5)),
    pw.SizedBox(height:4),
   ],
  ]);
  document.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(36),build:(_)=>pw.Column(
   crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
    pw.Center(child:pw.Text(TradeDocumentTermsSnapshot.title,style:pw.TextStyle(font:boldFont,fontSize:14))),
    pw.SizedBox(height:12),pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
     pw.Expanded(child:column(0,12)),pw.SizedBox(width:14),pw.Expanded(child:column(12,22)),
    ]),
   ])));
 }
}
