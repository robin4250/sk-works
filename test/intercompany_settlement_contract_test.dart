import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/intercompany_settlement.dart';

void main() {
  test('documents share one company-pair month key', () {
    const key = IntercompanySettlementKey(
      upperCompanyId: 'upper',
      lowerCompanyId: 'lower',
      year: 2026,
      month: 9,
    );
    expect(key.stableKey, 'upper:lower:2026-09');
    for (final kind in SettlementDocumentKind.values) {
      final ref = SettlementDocumentRef(
        settlementKey: key,
        kind: kind,
        documentId: kind.name,
      );
      expect(ref.settlementKey.stableKey, key.stableKey);
    }
  });

  test('both sides retain year and month folder views', () {
    expect(
      SettlementFolderPolicy.upperCompanyFolder(
        lowerCompanyName: 'A社',
        year: 2026,
        month: 9,
      ),
      '協力会社/A社/請求・精算/2026/09',
    );
    expect(
      SettlementFolderPolicy.lowerCompanyFolder(
        upperCompanyName: '親会社',
        year: 2026,
        month: 9,
      ),
      '取引先/親会社/請求・精算/2026/09',
    );
  });
}
