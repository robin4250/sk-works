import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';

void main() {
  List<TutorialEvidenceCheckpoint> policy(Map<String, dynamic>? value) =>
      TutorialEvidenceRepository.operationalCheckpoints('company_payroll_policy', value, 'company');
  test('unavailable policy has no display-default saved evidence', () {
    expect(policy(null).every((item) => item.state == TutorialEvidenceState.unknown), isTrue);
    expect(policy({}).any((item) => item.state == TutorialEvidenceState.saved), isFalse);
  });
  test('stored valid payroll policy and one selected reviewer complete', () {
    final rows = policy({'closing_day': 31, 'payment_day': 25, 'payment_month_offset': 2,
      'reviewers': [{'user_id': 'admin', 'selected_position': 1}]});
    expect(rows.every((item) => item.state == TutorialEvidenceState.saved), isTrue);
    expect(rows.every((item) => item.evidenceKey != null), isTrue);
  });
  test('invalid same-month timing and no reviewer remain missing', () {
    final rows = policy({'closing_day': 31, 'payment_day': 25, 'payment_month_offset': 0,
      'reviewers': []});
    expect(rows.where((item) => item.state == TutorialEvidenceState.missing).map((item) => item.key),
      containsAll(['payment_timing', 'reviewers']));
  });
  test('empty document selection has no fabricated no-documents completion', () {
    final rows = TutorialEvidenceRepository.operationalCheckpoints(
      'company_document_selection', {'rows': []}, 'company');
    expect(rows.single.state, TutorialEvidenceState.unknown);
  });
  test('qualification remains optional saved registration evidence', () {
    final rows = TutorialEvidenceRepository.operationalCheckpoints(
      'personal_qualifications', {'rows': [{'id': 'qualification'}]}, 'company');
    expect(rows.single.state, TutorialEvidenceState.saved);
    expect(rows.single.evidenceKey, contains('qualification'));
  });
}
