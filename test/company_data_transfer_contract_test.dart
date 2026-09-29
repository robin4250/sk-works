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
}
