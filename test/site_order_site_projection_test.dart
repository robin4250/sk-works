import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_site_projection.dart';

void main(){
  test('directory projection excludes financial fields, PDF references and free form notes',(){
    final source=<String,dynamic>{'source_site_id':'canonical-site','name':'現場A',
      'address':'東京都','latitude':35.6,'longitude':139.7,'status':'in_progress',
      'unit_price_yen':32000,'billing_contract_amount':1000000,'order_pdf_url':'secret',
      'pdf_storage_path':'private/order','notes':'単価32,000円','company_snapshot':{'price':32000},
      'orders':[{'amount':1000}]};
    final projected=SiteOrderSiteProjection.fromSource(source).toJson();
    expect(projected,{'source_site_id':'canonical-site','name':'現場A',
      'address':'東京都','latitude':35.6,'longitude':139.7,'status':'preparation'});
    projected['name']='changed';
    expect(SiteOrderSiteProjection.fromSource(source).toJson()['name'],'現場A');
  });
  test('unexpected nested data in a public field cannot escape the projection',(){
    expect(()=>SiteOrderSiteProjection.fromSource({'source_site_id':'site','name':'現場',
      'address':{'unit_price_yen':32000}}),throwsFormatException);
    expect(()=>SiteOrderSiteProjection.fromSource({'source_site_id':'site','name':'現場',
      'latitude':double.nan}),throwsFormatException);
    expect(()=>SiteOrderSiteProjection.fromSource({'source_site_id':'site','name':'現場',
      'longitude':200}),throwsFormatException);
  });
}
