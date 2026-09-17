import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/qualification.dart';

void main() {
  group('QualificationCatalog', () {
    const catalog = QualificationCatalog([
      QualificationMaster(
        id: 'foreman',
        name: '職長・安全衛生責任者',
        issuer: '講習機関',
      ),
      QualificationMaster(
        id: 'tamakake',
        name: '玉掛け技能講習',
        issuer: '技能講習機関',
      ),
    ]);

    test('finds a qualification by id', () {
      expect(catalog.findById('tamakake')?.name, '玉掛け技能講習');
    });

    test('searches by name or issuer', () {
      expect(catalog.search('玉掛け').single.id, 'tamakake');
      expect(catalog.search('講習機関'), hasLength(2));
    });
  });

  group('WorkerQualification', () {
    test('detects expired certificates', () {
      final item = WorkerQualification(
        workerId: 'worker-1',
        qualificationId: 'q-1',
        expiryDate: DateTime(2026, 9, 1),
      );

      expect(item.isExpiredOn(DateTime(2026, 9, 17)), isTrue);
      expect(item.isExpiredOn(DateTime(2026, 8, 31)), isFalse);
    });

    test('detects certificates expiring within a window', () {
      final item = WorkerQualification(
        workerId: 'worker-1',
        qualificationId: 'q-1',
        expiryDate: DateTime(2026, 10, 1),
      );

      expect(
        item.expiresWithin(DateTime(2026, 9, 17), const Duration(days: 30)),
        isTrue,
      );
    });
  });
}
