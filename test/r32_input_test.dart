import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/r32_input.dart';

void main() {
  const input = R32Input(actorId: 'actor', companyId: 'company', subjectId: 'invoice',
    sourceRevision: '2026-10-17T00:00:00Z', text: '鳶工・安全設備・足場組み立て解体作業');
  const workspace = <String, dynamic>{'company_id': 'company',
    'source_revision': '2026-10-17T09:00:00+09:00', 'attachment': null};
  Map<String, dynamic> apply({Map<String, dynamic> payload = const {},
    Map<String, dynamic> data = workspace, String? actor = 'actor',
    String kind = 'invoice', String subject = 'invoice',
    String revision = '2026-10-17T00:00:00Z'}) => input.apply(payload: payload,
      workspace: data, actor: actor, subjectKind: kind, subject: subject, revision: revision);

  test('same preview source fills only its blank initial text and preserves amounts', () {
    final payload = {'work_name': '', 'month': '2026-10', 'total_amount_yen': 110000,
      'tax_amount_yen': 10000, 'period_start': '2026-10-01'};
    final result = apply(payload: payload);
    expect(result['work_name'], input.text);
    expect(payload['work_name'], '');
    for (final key in ['month', 'total_amount_yen', 'tax_amount_yen', 'period_start']) {
      expect(result[key], payload[key]);
    }
  });
  test('saved blank or edited text and explicit server defaults never get replaced', () {
    for (final text in ['', '既存の工事名']) {
      final payload = {'work_name': text};
      expect(apply(payload: payload, data: {...workspace, 'attachment': {'version': 1}}), payload);
    }
    expect(apply(payload: {'work_name': 'server'})['work_name'], 'server');
  });
  test('actor, company, subject, revision or document kind mismatch never transfers text', () {
    expect(apply(actor: 'other'), isEmpty);
    expect(apply(actor: null), isEmpty);
    expect(apply(data: {...workspace, 'company_id': 'other'}), isEmpty);
    expect(apply(subject: 'other'), isEmpty);
    expect(apply(revision: '2026-10-18T00:00:00Z'), isEmpty);
    expect(apply(kind: 'payment_certificate'), isEmpty);
    expect(apply(data: {...workspace, 'source_revision': '2026-10-18T00:00:00Z'}), isEmpty);
    expect(apply(data: {...workspace, 'source_revision': null}), isEmpty);
  });
  test('legacy company identity and blank or oversized text require manual confirmation', () {
    for (final value in [
      const R32Input(actorId: 'actor', companyId: '', subjectId: 'invoice', sourceRevision: '2026-10-17T00:00:00Z', text: 'subject'),
      const R32Input(actorId: 'actor', companyId: 'company', subjectId: 'invoice', sourceRevision: '2026-10-17T00:00:00Z', text: ' '),
      R32Input(actorId: 'actor', companyId: 'company', subjectId: 'invoice', sourceRevision: '2026-10-17T00:00:00Z', text: List.filled(241, '工').join()),
    ]) {
      expect(value.apply(payload: {}, workspace: workspace, actor: 'actor', subjectKind: 'invoice',
        subject: 'invoice', revision: '2026-10-17T00:00:00Z'), isEmpty);
    }
  });
}
