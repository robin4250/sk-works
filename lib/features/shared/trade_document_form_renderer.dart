import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../invoices/invoice_order_acceptance_pdf.dart';
import '../payroll/payment_order_pdf.dart';
import 'company_seal_pdf.dart';
import 'trade_document_attachment.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'trade_document_form_pdf.dart';
import 'trade_document_terms_pdf.dart';
import 'trade_document_output_layout.dart';

/// Pure rendering from a verified immutable payload; never fetches live parties,
/// a new stamp, bank data or a different legal version.
class TradeDocumentFormRenderer {
 const TradeDocumentFormRenderer._();
 static Future<Uint8List> canonical(Map<String,dynamic> payload)async {
  final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':payload});
  final font=await CompanySealPdf.loadFont(),document=pw.Document(theme:pw.ThemeData.withFont(base:font,bold:font));
  if(payload['kind']=='order'){await PaymentOrderPdf.append(document,attachment,regularFont:font,boldFont:font);}
  else{await InvoiceOrderAcceptancePdf.append(document,attachment,regularFont:font,boldFont:font);}
  return document.save();
 }
 static Future<Uint8List> output(Map<String,dynamic> payload,{required TradeDocumentOutputLayout layout,required Uint8List canonicalBytes})async {
  TradeDocumentAttachment.fromJson({'version':1,'payload':payload});
  if(layout==TradeDocumentOutputLayout.a4TwoPages)return canonicalBytes;
  // Derivatives are supported only for the exact adopted two-page contract.
  // Never attach new terms to a legacy or otherwise unknown original.
  TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
  final font=await CompanySealPdf.loadFont();
  return composeTradeDocumentOutput(layout:layout,canonicalBytes:canonicalBytes,
   frontA4:()=>TradeDocumentFormPdf.buildCanvas(payload,regularFont:font,boldFont:font),
   termsA4:()async=>TradeDocumentTermsPdf.buildCanvas(payload,regularFont:font,boldFont:font));
 }

}
