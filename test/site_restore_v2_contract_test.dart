import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site restore uses production v2 approval and photo contracts', () {
    final repository =
        File('lib/features/sites/site_cloud_repository.dart').readAsStringSync();
    final model = File('lib/features/sites/site_page.dart').readAsStringSync();

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
  });
}
