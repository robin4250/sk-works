import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_data_transfer.dart';

void main() {
  test('personnel bundle is the largest payload', () {
    const transfer = CompanyDataTransfer(
      id: 't1',
      sourceCompanyId: 'c1',
      currentCompanyId: 'c1',
      targetCompanyId: 'c2',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.personnelBundle,
    );
    expect(transfer.includesPersonnel, isTrue);
    expect(transfer.includesQualifications, isTrue);
    expect(transfer.includesDocuments, isTrue);
  });

  test('qualification and document sends remain scoped', () {
    const qualification = CompanyDataTransfer(
      id: 't1',
      sourceCompanyId: 'c1',
      currentCompanyId: 'c1',
      targetCompanyId: 'c2',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.qualificationsOnly,
    );
    expect(qualification.includesPersonnel, isFalse);
    expect(qualification.includesQualifications, isTrue);
    expect(qualification.includesDocuments, isFalse);
  });

  test('send requires explicit final confirmation', () {
    const pending = TransferConfirmation(
      targetCompanyId: 'parent',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.personnelBundle,
      confirmed: false,
    );
    expect(pending.canSend, isFalse);
  });
  test('forwarding preserves origin and prior transfer provenance', () {
    const received = CompanyDataTransfer(
      id: 'c-to-b',
      sourceCompanyId: 'company-c',
      currentCompanyId: 'company-c',
      targetCompanyId: 'company-b',
      workerIds: <String>['w1', 'w2'],
      kind: TransferPayloadKind.qualificationsOnly,
    );

    final forwarded = received.forward(
      id: 'b-to-a',
      forwardingCompanyId: 'company-b',
      targetCompanyId: 'company-a',
    );

    expect(forwarded.sourceCompanyId, 'company-b');
    expect(forwarded.currentCompanyId, 'company-b');
    expect(forwarded.targetCompanyId, 'company-a');
    expect(forwarded.originCompanyId, 'company-c');
    expect(forwarded.forwardedFromTransferId, 'c-to-b');
    expect(forwarded.workerIds, <String>['w1', 'w2']);
    expect(forwarded.kind, TransferPayloadKind.qualificationsOnly);
  });

  test('second forwarding keeps the original company', () {
    const first = CompanyDataTransfer(
      id: 'd-to-c',
      sourceCompanyId: 'company-d',
      currentCompanyId: 'company-d',
      targetCompanyId: 'company-c',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.documentsOnly,
    );

    final cToB = first.forward(
      id: 'c-to-b',
      forwardingCompanyId: 'company-c',
      targetCompanyId: 'company-b',
    );
    final bToA = cToB.forward(
      id: 'b-to-a',
      forwardingCompanyId: 'company-b',
      targetCompanyId: 'company-a',
    );

    expect(bToA.originCompanyId, 'company-d');
    expect(bToA.forwardedFromTransferId, 'c-to-b');
  });

}
