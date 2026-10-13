import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_recognition_service.dart';

void main() {
  const service = QualificationRecognitionService();

  test('matches recognized qualification against existing master', () {
    final candidate = service.fromRecognizedText(
      recognizedText: '玉掛け技能講習修了証\n氏名：山田 太郎\n有効期限 2029年3月15日',
      masters: const [
        {'id': 'm1', 'name': '玉掛け技能講習修了証'},
      ],
      aliases: const [],
    );

    expect(candidate.matchedMasterId, 'm1');
    expect(candidate.matchedMasterName, '玉掛け技能講習修了証');
    expect(candidate.personName, '山田 太郎');
    expect(candidate.expiresAt, DateTime(2029, 3, 15));
  });

  test('matches spelling variation through qualification master alias', () {
    final candidate = service.fromRecognizedText(
      recognizedText: '高所作業車 運転技能講習\n氏名\n鈴木一郎',
      masters: const [
        {'id': 'm2', 'name': '高所作業車運転技能講習修了証'},
      ],
      aliases: const [
        {
          'qualification_master_id': 'm2',
          'alias_name': '高所作業車 運転技能講習',
        },
      ],
    );

    expect(candidate.matchedMasterId, 'm2');
    expect(candidate.personName, '鈴木一郎');
  });

  test('returns review candidate instead of auto-registering unknown text', () {
    final candidate = service.fromRecognizedText(
      recognizedText: '新しい特別教育 修了証\n氏名：佐藤花子',
      masters: const [],
      aliases: const [],
    );

    expect(candidate.matchedExistingMaster, isFalse);
    expect(candidate.qualificationName, contains('特別教育'));
    expect(candidate.personName, '佐藤花子');
  });
}
