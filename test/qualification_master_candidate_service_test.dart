import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_master_candidate_service.dart';

void main() {
  const service = QualificationMasterCandidateService();

  test('groups exact formatting variants into one new master candidate', () {
    final result = service.buildCandidates(
      recognizedQualificationNames: const [
        '玉掛け 技能講習',
        '玉掛け技能講習',
        '玉掛け・技能講習',
      ],
      masters: const [],
      aliases: const [],
    );

    expect(result, hasLength(1));
    expect(result.single.occurrences, 3);
    expect(result.single.variants, hasLength(3));
    expect(result.single.needsNewMaster, isTrue);
  });

  test('maps recognized aliases to an existing master', () {
    final result = service.buildCandidates(
      recognizedQualificationNames: const [
        '高所作業車 運転技能講習',
        '高所作業車運転技能講習',
      ],
      masters: const [
        {'id': 'm1', 'name': '高所作業車運転技能講習修了証'},
      ],
      aliases: const [
        {
          'qualification_master_id': 'm1',
          'alias_name': '高所作業車運転技能講習',
        },
      ],
    );

    expect(result, hasLength(1));
    expect(result.single.existingMasterId, 'm1');
    expect(result.single.existingMasterName, '高所作業車運転技能講習修了証');
    expect(result.single.needsNewMaster, isFalse);
    expect(result.single.occurrences, 2);
  });

  test('keeps unrelated qualifications as separate candidates', () {
    final result = service.buildCandidates(
      recognizedQualificationNames: const [
        '玉掛け技能講習',
        'フォークリフト運転技能講習',
      ],
      masters: const [],
      aliases: const [],
    );

    expect(result, hasLength(2));
  });
}
