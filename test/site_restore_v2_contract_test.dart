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

    expect(repository, contains("rpc('site_directory_rows_v2')"));
    expect(repository, contains("rpc('site_directory_metadata')"));
    expect(repository, contains("rpc(\n      'site_information_request'"));
    expect(repository, contains("rpc(\n      'site_photo_request'"));
    expect(repository, contains("from('site_entrance_photos')"));
    expect(repository, contains("from('site-entrance-photos')"));
    expect(repository, contains("'slot': slot"));
    expect(model, contains('nearestStation'));
    expect(model, contains('representativeName'));
    expect(model, contains('representativePhone'));
    expect(model, contains('creatorName'));
    expect(model, contains('createdAt'));
    expect(model, contains('updatedAt'));
    expect(detail, contains("'取引先に共有'"));
    expect(detail, contains("'編集／登録'"));
    expect(detail, contains("'最寄駅'"));
    expect(detail, contains("'現場責任者'"));
    expect(detail, contains("scheme: 'tel'"));
    expect(detail, contains("'maps.apple.com'"));
    expect(detail, contains("'登録者'"));
    expect(detail, contains('for (var slot = 1; slot <= 3; slot++)'));
    expect(detail, contains("'変更申請を送信しました'"));
    expect(cloud, contains('SiteDetailPage('));
  });
}
