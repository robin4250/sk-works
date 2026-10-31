// Legacy pure evaluator remains covered; the production canonical wire is
// verified in canonical_document_guide_receipt_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';

const _company = '10000000-0000-0000-0000-000000000002';
const _worker = '10000000-0000-0000-0000-000000000003';
const _updated = '2026-10-29T00:00:00Z';
const _bank = {'worker_id': _worker, 'company_id': _company, 'updated_at': _updated};
const _requirements = [
  {'id': 'bank', 'name': '銀行口座情報', 'is_active': true, 'is_required': true, 'expiry_required': false},
  {'id': 'health', 'name': '健康診断書', 'is_active': true, 'is_required': true, 'expiry_required': true},
];
const _statuses = [
  {'id': 'synthetic-bank-status', 'worker_id': _worker, 'requirement_id': 'bank', 'status': 'submitted',
    'attachment_path': 'synthetic/metadata-is-not-account-evidence'},
  {'id': 'synthetic-health-status', 'worker_id': _worker, 'requirement_id': 'health', 'status': 'submitted',
    'attachment_path': 'synthetic/retained-object', 'expires_at': '2027-01-01'},
];
Map<String, dynamic> _documents({bool known = true, Object? metadata = _bank, bool exempt = false}) => {
  'company_id': _company, 'worker_id': _worker, 'requirements': _requirements, 'statuses': _statuses,
  'bank_account_known': known, 'bank_account_metadata': metadata,
  'exemptions': [if (exempt) {'worker_id': _worker, 'requirement_id': 'bank',
    'active': true, 'version': 1, 'reason': 'synthetic exemption'}],
};
TutorialEvidenceCheckpoint _bankCheckpoint(Map<String, dynamic> docs) =>
  TutorialEvidenceRepository.documentCheckpoints(docs, today: DateTime(2026, 10, 29))
    .singleWhere((item) => item.key == 'document:bank');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bank evidence uses exact scoped saved metadata, never document photo/status', () {
    final saved = _bankCheckpoint(_documents());
    expect(saved.state, TutorialEvidenceState.saved);
    expect(saved.evidenceKey, 'bank:$_worker:$_updated');
    expect(_bankCheckpoint(_documents(metadata: null)).state, TutorialEvidenceState.missing);
    for (final docs in [
      _documents(known: false), _documents(metadata: {..._bank, 'worker_id': 'another-worker'}),
      _documents(metadata: {..._bank, 'company_id': 'another-company'}),
      _documents(metadata: {..._bank, 'updated_at': 'invalid'}),
    ]) {
      final item = _bankCheckpoint(docs);
      expect(item.state, TutorialEvidenceState.unknown); expect(item.evidenceKey, isNull);
    }
    expect(_bankCheckpoint(_documents(metadata: null, exempt: true)).state, TutorialEvidenceState.notApplicable);
  });

}
