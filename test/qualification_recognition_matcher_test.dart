import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_recognition_matcher.dart';

void main() {
  const matcher = QualificationRecognitionMatcher();

  test('matches canonical qualification and alias without auto-confirming', () {
    final result = matcher.buildCandidate(
      rawText: '玉掛け技能講習修了証\n氏名 山田太郎\n有効期限 2029年3月31日',
      masters: const [
        {'id': 'm1', 'name': '玉掛け技能講習'},
      ],
      aliases: const [
        {'qualification_master_id': 'm1', 'alias_name': '玉掛け'},
      ],
      knownWorkerNames: const ['山田太郎'],
    );

    expect(result.qualificationCandidates, isNotEmpty);
    expect(result.qualificationCandidates.first.masterId, 'm1');
    expect(result.personName, '山田太郎');
    expect(result.expiresAt, DateTime(2029, 3, 31));
  });

  test('extracts certificate number as a review candidate', () {
    final result = matcher.buildCandidate(
      rawText: 'フォークリフト運転技能講習\n修了証番号 AB-123456',
      masters: const [
        {'id': 'm2', 'name': 'フォークリフト運転技能講習'},
      ],
      aliases: const [],
    );

    expect(result.certificateNumber, 'AB-123456');
    expect(result.qualificationCandidates.first.canonicalName,
        'フォークリフト運転技能講習');
  });

  test('unknown text stays unconfirmed and creates no fake master match', () {
    final result = matcher.buildCandidate(
      rawText: '判読できないカード 2028/01/01',
      masters: const [
        {'id': 'm1', 'name': '玉掛け技能講習'},
      ],
      aliases: const [],
    );

    expect(result.qualificationCandidates, isEmpty);
  });
}
