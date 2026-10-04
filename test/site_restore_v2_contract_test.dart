import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site restore uses production v2 approval and photo contracts', () {
    final repository =
        File('lib/features/sites/site_cloud_repository.dart').readAsStringSync();
    final model = File('lib/features/sites/site_page.dart').readAsStringSync();
    final detail =
        File('lib/features/sites/site_detail_page.dart').readAsStringSync();
    final cloud =
        File('lib/features/sites/site_cloud_page.dart').readAsStringSync();
    final siteMap =
        File('lib/features/sites/site_map_page.dart').readAsStringSync();
    final siteMapRepo =
        File('lib/features/sites/site_map_repository.dart').readAsStringSync();
    final siteMapSql = File(
      'supabase/migrations/20261001220418_add_site_map_workspace.sql',
    ).readAsStringSync();

    expect(repository, contains("rpc('site_directory_rows_v2')"));
    expect(repository, contains("rpc('site_directory_metadata')"));
    expect(repository, contains("site_information_request"));
    expect(repository, contains("site_photo_request"));
    expect(repository, contains('loadSiteShareTargets'));
    expect(repository, contains('sendSiteShare'));
    expect(repository, contains("from('site_entrance_photos')"));
    expect(repository, contains("from('site-entrance-photos')"));
    expect(model, contains('nearestStation'));
    expect(model, contains('representativeName'));
    expect(model, contains('representativePhone'));
    expect(model, contains('creatorName'));
    expect(model, contains('createdAt'));
    expect(model, contains('updatedAt'));
    expect(detail, contains("'下請け会社・取引会社に共有'"));
    expect(detail, contains("'編集／登録'"));
    expect(detail, contains("'現場住所'"));
    expect(detail, contains("'最寄駅'"));
    expect(detail, contains("'現場責任者'"));
    expect(detail, contains("'電話番号'"));
    expect(detail, contains("'登録者の社員情報'"));
    expect(detail, contains("'登録日:"));
    expect(detail, contains("'最終更新日:"));
    expect(detail, contains("Uri.https('www.google.com'"));
    expect(detail, contains("'/maps/search/'"));
    expect(detail, contains("scheme: 'tel'"));
    expect(detail, contains("'確定して申請'"));
    expect(detail, contains("for (var slot = 1; slot <= 3; slot++)"));
    expect(detail, contains("'カメラで撮影'"));
    expect(detail, contains("'写真ライブラリから選択'"));
    expect(detail, contains('ImageSource.gallery'));
    expect(detail, contains('InteractiveViewer'));
    expect(detail, contains("tooltip: _tr('写真を変更', 'Change Photo')"));
    expect(detail, contains("title: Text(SkoLanguageController.isEnglish ? 'Site Photo \$slot' : '現場写真\$slot')"));
    expect(detail, contains("'formal_name'"));
    expect(detail, contains("'nearest_station'"));
    expect(detail, contains("'representative_name'"));
    expect(detail, contains("'representative_phone'"));
    expect(cloud, contains("'現場名・取引先・担当者・住所・最寄駅で検索'"));
    expect(cloud, contains('SiteDetailPage('));
    expect(cloud, contains("SkoLanguageController.tr('現場マップ')"));
    expect(cloud, contains("SkoLanguageController.tr('現場登録')"));
    expect(cloud, contains('SiteMapPage()'));
    expect(siteMap, contains("'全従業員の自宅'"));
    expect(siteMap, contains("'自宅（本人）'"));
    expect(siteMap, contains("'現場マップ'"));
    expect(siteMap, contains("'最新の打刻位置'"));
    expect(siteMapRepo, contains("rpc('site_map_workspace')"));
    expect(siteMapSql, contains("v_role in ('owner','admin','manager')"));
    expect(siteMapSql, contains('a.worker_id=v_worker'));
  });
}
