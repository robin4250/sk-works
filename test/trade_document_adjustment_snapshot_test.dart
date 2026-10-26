import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_adjustment_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';

void main() {
  const id='11111111-1111-4111-8111-111111111111';
  Map<String,dynamic> item()=>{'entry_id':id,'title':'資材調整','amount_yen':50,
    'sign':'minus','calculation_mode':'settlement_yen'};
  test('historical snapshot without manual entries stays empty', () {
    expect(SavedTradeDocumentAdjustment.parse({}),isEmpty);
  });
  test('saved negative final item preserves sign and exact amount', () {
    final result=SavedTradeDocumentAdjustment.parse({'document_adjustments_v1':[item()]});
    expect(result.single.signedYen,-50);expect(result.single.isFinalAmount,true);
  });
  test('duplicate identity and fractional or missing money reject output', () {
    expect(()=>SavedTradeDocumentAdjustment.parse({'document_adjustments_v1':[item(),item()]}),throwsFormatException);
    expect(()=>SavedTradeDocumentAdjustment.parse({'document_adjustments_v1':[{...item(),'amount_yen':1.5}]}),throwsFormatException);
    expect(()=>SavedTradeDocumentAdjustment.parse({'document_adjustments_v1':[{...item(),'entry_id':null}]}),throwsFormatException);
  });
  test('final adjustment is printed separately and saved tax and total stay exact', () {
    final invoice=InvoiceEngine.calculate(customerId:'検証取引会社',billingPeriod:'2026年10月',
      detailMode:InvoiceDetailMode.siteBreakdownOnInvoice,sites:const [],
      subtotalYenOverride:105,taxYenOverride:11,grandTotalYenOverride:66,
      documentAdjustments:SavedTradeDocumentAdjustment.parse({'document_adjustments_v1':[item()]}));
    expect(invoice.taxYen,11);expect(invoice.grandTotalYen,66);
    final text=InvoicePdfService.buildTextSnapshot([invoice]);
    expect(text,contains('資材調整（追加税なし）'));expect(text,contains('消費税'));
    expect(text,contains('66'));
  });
}
