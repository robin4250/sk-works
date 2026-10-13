import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_recognition_matcher.dart';
import 'package:sk_works/features/qualifications/qualification_recognition_review_page.dart';

void main() {
  testWidgets('OCR candidate requires explicit review before registration',
      (tester) async {
    const candidate = QualificationRecognitionCandidate(
      rawText: '玉掛け技能講習修了証\n山田太郎',
      personName: '山田太郎',
      certificateNumber: 'AB-1234',
      expiresAt: null,
      qualificationCandidates: [
        QualificationMasterCandidate(
          masterId: 'm1',
          canonicalName: '玉掛け技能講習',
          matchedText: '玉掛け',
          score: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: QualificationRecognitionReviewPage(candidate: candidate),
      ),
    );

    expect(find.text('資格証の読み取り内容を確認'), findsOneWidget);
    expect(find.textContaining('登録前に必ず'), findsOneWidget);
    expect(find.text('この内容で登録へ進む'), findsOneWidget);
    expect(find.text('玉掛け技能講習'), findsWidgets);
    expect(find.text('山田太郎'), findsOneWidget);
  });
}
