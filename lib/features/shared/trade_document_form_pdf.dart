import 'package:pdf/widgets.dart' as pw;
import '../../domain/trade_document_form_draft.dart';
import 'trade_document_form_pdf_v1.dart';
import 'trade_document_form_pdf_v2.dart';

/// Explicit form schema selects its frozen renderer, never its current status,
/// company profile, date, or app release. Missing fields remain the original v1.
class TradeDocumentFormPdf {
 const TradeDocumentFormPdf._();
 static bool _v2(Map<String,dynamic> payload) => payload.containsKey('form_fields') &&
  TradeDocumentFormFields.fromJson(payload['form_fields']).toJson()['schema']==2;
 static Future<void> append(pw.Document document,Map<String,dynamic> payload,
  {required pw.Font regularFont,required pw.Font boldFont}) => _v2(payload)
   ? TradeDocumentFormPdfV2.append(document,payload,regularFont:regularFont,boldFont:boldFont)
   : TradeDocumentFormPdfV1.append(document,payload,regularFont:regularFont,boldFont:boldFont);
 static Future<pw.Widget> buildCanvas(Map<String,dynamic> payload,
  {required pw.Font regularFont,required pw.Font boldFont}) => _v2(payload)
   ? TradeDocumentFormPdfV2.buildCanvas(payload,regularFont:regularFont,boldFont:boldFont)
   : TradeDocumentFormPdfV1.buildCanvas(payload,regularFont:regularFont,boldFont:boldFont);
}
