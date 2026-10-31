import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/required_document_evidence.dart';

String uuid(int n) =>
    '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> item(
  int id,
  String state, {
  String name = '銀行口座',
  String scope = 'internal',
}) => {
  'requirement_id': uuid(id),
  'name': name,
  'scope': scope,
  'state': state,
  'evidence_key': state == 'saved' ? 'bank:synthetic' : null,
  'status_label': state == 'saved' ? '保存済み' : state,
};
Map<String, dynamic> receipt(List<Map<String, dynamic>> items) => {
  'capability_version': 1,
  'evidence_contract_version': 1,
  'company_id': uuid(1),
  'worker_id': uuid(2),
  'actor_id': uuid(3),
  'session_id': uuid(4),
  'items': items,
  'required_count': items.where((v) => v['state'] != 'exempt').length,
  for (final state in ['saved', 'missing', 'unknown', 'exempt'])
    '${state}_count': items.where((v) => v['state'] == state).length,
  for (final state in ['missing', 'unknown'])
    '${state}_names': items
        .where((v) => v['state'] == state)
        .map((v) => v['name'])
        .toList(),
};
void main() {
  test('bank saved and exempt remain distinct evidence states', () {
    final value = RequiredDocumentEvidenceSnapshot.fromJson(
      receipt([item(10, 'saved'), item(11, 'exempt')]),
    );
    expect(value.savedCount, 1);
    expect(value.exemptCount, 1);
    expect(value.requiredCount, 1);
    expect(value.items.first.state, RequiredDocumentEvidenceState.saved);
    expect(value.items.first.statusLabel, '保存済み');
    expect(value.items.last.state, RequiredDocumentEvidenceState.exempt);
    expect(value.items.last.evidenceKey, isNull);
    expect(() => value.items.clear(), throwsUnsupportedError);
  });
  test(
    'same names with distinct requirement IDs and scopes retain multiplicity',
    () {
      final raw = receipt([
        item(10, 'missing'),
        item(11, 'missing', scope: 'upstream'),
      ]);
      final value = RequiredDocumentEvidenceSnapshot.fromJson(raw);
      expect(value.items.map((v) => v.scope), ['internal', 'upstream']);
      expect(value.missingCount, 2);
      expect(value.missingNames, ['銀行口座', '銀行口座']);
      raw['missing_names'] = ['銀行口座'];
      expect(
        () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
        throwsFormatException,
      );
    },
  );
  test(
    'empty items are a known zero receipt and extra fields confer no state',
    () {
      final raw = receipt([])..['submitted'] = true;
      final value = RequiredDocumentEvidenceSnapshot.fromJson(raw);
      expect(value.items, isEmpty);
      expect(value.requiredCount, 0);
      expect(value.unknownCount, 0);
      expect(value.companyId, uuid(1));
      expect(value.actorId, uuid(3));
      expect(value.sessionId, uuid(4));
    },
  );
  test('unknown remains unknown without saved evidence', () {
    final value = RequiredDocumentEvidenceSnapshot.fromJson(
      receipt([item(10, 'unknown', scope: 'both')]),
    );
    expect(value.items.single.state, RequiredDocumentEvidenceState.unknown);
    expect(value.unknownNames, ['銀行口座']);
    expect(value.savedCount, 0);
    expect(value.missingCount, 0);
  });
  test('reject duplicate IDs even across scopes', () {
    final raw = receipt([
      item(10, 'missing'),
      item(10, 'missing', scope: 'upstream'),
    ]);
    expect(
      () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
      throwsFormatException,
    );
  });
  test('reject malformed contract and identity fields', () {
    for (final entry in <String, dynamic>{
      'capability_version': 1.0,
      'evidence_contract_version': 2,
      'company_id': 'not-a-uuid',
      'worker_id': null,
      'actor_id': '',
      'session_id': uuid(4).replaceAll('-', ''),
      'items': {},
      'missing_names': '銀行口座',
      'unknown_names': [null],
    }.entries) {
      final raw = receipt([])..[entry.key] = entry.value;
      expect(
        () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });
  test(
    'reject mismatched or noninteger counts and mismatched name multisets',
    () {
      for (final field in [
        'required_count',
        'saved_count',
        'missing_count',
        'unknown_count',
        'exempt_count',
      ]) {
        for (final bad in [-1, 0.0, 99]) {
          final raw = receipt([item(10, 'missing')])..[field] = bad;
          expect(
            () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
            throwsFormatException,
            reason: '$field=$bad',
          );
        }
      }
      for (final state in ['missing', 'unknown']) {
        final raw = receipt([item(10, state)])..['${state}_names'] = ['別名'];
        expect(
          () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'reject malformed item, invalid state and saved without a nonempty key',
    () {
      for (final entry in <String, dynamic>{
        'requirement_id': 'invalid',
        'name': ' ',
        'scope': 'foreign',
        'state': 'submitted',
        'status_label': null,
        'evidence_key': 42,
      }.entries) {
        final row = item(10, 'saved')..[entry.key] = entry.value;
        expect(
          () => RequiredDocumentEvidenceSnapshot.fromJson(receipt([row])),
          throwsFormatException,
          reason: entry.key,
        );
      }
      for (final key in [null, '', ' ']) {
        final row = item(10, 'saved')..['evidence_key'] = key;
        expect(
          () => RequiredDocumentEvidenceSnapshot.fromJson(receipt([row])),
          throwsFormatException,
        );
      }
      final raw = receipt([])..['items'] = [null];
      expect(
        () => RequiredDocumentEvidenceSnapshot.fromJson(raw),
        throwsFormatException,
      );
    },
  );
}
