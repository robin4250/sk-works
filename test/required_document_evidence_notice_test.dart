import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/required_document_evidence_notice.dart';

RequiredDocumentAttention attention({List<String> unknown = const [], bool unavailable = false}) =>
  RequiredDocumentAttention(missingCount: 0, missingNames: const [], needsLicense: false,
    needsQualification: false, unknownDocumentNames: unknown, documentEvidenceUnavailable: unavailable);

void main() {
  testWidgets('unknown document evidence remains visible without creating pending obligations', (tester) async {
    var opened = false;
    final value = attention(unknown: ['synthetic document']);
    expect(value.unresolvedCount, 0);
    expect(value.hasMissing, isFalse);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RequiredDocumentEvidenceNotice(
      attention: value, onOpen: () => opened = true))));
    expect(find.text('書類の確認状況'), findsOneWidget);
    expect(find.text('未確定 1'), findsOneWidget);
    expect(find.text('要対応'), findsNothing);
    await tester.tap(find.text('書類の確認状況'));
    expect(opened, isTrue);
  });
  testWidgets('unavailable evidence is never shown as zero pending success', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RequiredDocumentEvidenceNotice(
      attention: attention(unavailable: true), onOpen: () {}))));
    expect(find.text('状態を確認できません。再読み込みしてください。'), findsOneWidget);
    expect(find.text('未確定 0'), findsNothing);
  });
  testWidgets('resolved or explicitly exempt evidence has no remaining notice', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RequiredDocumentEvidenceNotice(
      attention: attention(), onOpen: () {}))));
    expect(find.byType(ListTile), findsNothing);
  });
}
