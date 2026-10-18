import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/registered_site_search.dart';
import 'package:sk_works/features/sites/site_page.dart';

void main() {
  const first = SiteRecord(
    id: 'A1234567-0000-0000-0000-000000000001',
    name: '短縮現場', customerName: '取引会社', status: SiteStatus.active,
    address: '住所墨田', managerName: '担当佐藤', nearestStation: '最寄押上',
    formalName: '正式建設工事', representativeName: '責任田中', notes: '備考夜間',
  );
  const second = SiteRecord(
    id: 'b9876543-0000-0000-0000-000000000002',
    name: '別現場', customerName: '別会社', status: SiteStatus.completed,
  );
  const sameName = SiteRecord(
    id: 'c0000000-0000-0000-0000-000000000003',
    name: '短縮現場', customerName: '別会社', status: SiteStatus.paused,
  );
  const sites = [first, second, sameName];
  test('registered ID matches exactly, partially and case-insensitively', () {
    expect(filterRegisteredSites(sites, query: first.id), [first]);
    expect(filterRegisteredSites(sites, query: ' a1234567 '), [first]);
    expect(filterRegisteredSites(sites, query: 'B9876543'), [second]);
    expect(filterRegisteredSites(sites, query: 'not-loaded-site-id'), isEmpty);
  });
  for (final term in ['短縮現場', '取引会社', '住所墨田', '担当佐藤', '最寄押上',
    '正式建設工事', '責任田中', '備考夜間']) {
    test('existing text field remains searchable: $term', () {
      final matches = filterRegisteredSites(sites, query: term);
      expect(matches, contains(same(first)));
      expect(matches, isNot(contains(second)));
    });
  }
  test('status still restricts text and ID results', () {
    expect(filterRegisteredSites(sites, query: first.id, status: SiteStatus.completed), isEmpty);
    expect(filterRegisteredSites(sites, query: '短縮現場', status: SiteStatus.paused), [sameName]);
    expect(filterRegisteredSites(sites, status: SiteStatus.active), [first]);
  });
  test('empty query keeps source order and identities without merging same names', () {
    final result = filterRegisteredSites(sites, query: '  ');
    expect(result, orderedEquals(sites));
    expect(result[0], same(first)); expect(result[2], same(sameName));
    expect(sites, [first, second, sameName]);
  });
}
