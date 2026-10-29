import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/trade_document_terms_snapshot.dart';

/// The adopted back uses explicit baseline geometry, without paragraph padding.
/// This keeps all original words while matching the approved 6.5pt / 8.14pt page.
class TradeDocumentTermsPdf {
 const TradeDocumentTermsPdf._();
 static void append(pw.Document document,Map<String,dynamic> payload,
  {required pw.Font regularFont,required pw.Font boldFont}) {
  if(!payload.containsKey('contract_terms'))return;
  final terms=TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
  document.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:pw.EdgeInsets.zero,build:(_)=>pw.LayoutBuilder(builder:(context,constraints){
   final font=boldFont.getFont(context),width=PdfPageFormat.a4.width-68,height=PdfPageFormat.a4.height;
   const size=6.5,leading=8.14;
   final lines=<String>[];
   void wrap(String value){
    var line='';
    for(final rune in value.runes){
     final character=String.fromCharCode(rune);
     if(line.isNotEmpty&&font.stringMetrics('$line$character').advanceWidth*size>width){lines.add(line);line=character;}
     else{line+=character;}
    }
    if(line.isNotEmpty)lines.add(line);
   }
   final articles=terms.articles;
   for(var index=0;index<articles.length;index++){
    wrap('（${articles[index].$1}）');
    for(var part=0;part<articles[index].$2.length;part++){
     wrap('${part==0?'第${index+1}条　':'　　　　'}${articles[index].$2[part]}');
    }
   }
   // Reject an unsupported metric/font change rather than dropping or clipping text.
   if(lines.length>92||height-61-(lines.length-1)*leading-font.descent.abs()*size<34){throw StateError('確定条項の版面を確認できません。');}
   return pw.CustomPaint(size:PdfPoint(PdfPageFormat.a4.width,height),painter:(canvas,_) {
    canvas.drawString(font,12,TradeDocumentTermsSnapshot.title,34,height-44);
    for(var index=0;index<lines.length;index++){
     // PdfGraphics' direct glyph path paints this font's ideographic-space glyph
     // visibly. Reserve its exact advance, but paint only the non-space runs.
     final runs=lines[index].split('　');var cursor=34.0;
     for(var run=0;run<runs.length;run++){
      if(runs[run].isNotEmpty)canvas.drawString(font,size,runs[run],cursor,height-61-index*leading);
      cursor+=font.stringMetrics(runs[run]).advanceWidth*size;
      if(run<runs.length-1)cursor+=font.stringMetrics('　').advanceWidth*size;
     }
    }
   });
  })));
 }
}
