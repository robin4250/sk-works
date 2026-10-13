import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_data_transfer.dart';
import 'package:sk_works/domain/subcontractor_transfer_folder.dart';

void main() {
  test('received transfers are grouped by preserved origin company', () {
    const direct = CompanyDataTransfer(
      id: 'c-to-b',
      sourceCompanyId: 'company-c',
      currentCompanyId: 'company-c',
      targetCompanyId: 'company-b',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.personnelBundle,
    );
    const forwarded = CompanyDataTransfer(
      id: 'b-to-a',
      sourceCompanyId: 'company-b',
      currentCompanyId: 'company-b',
      targetCompanyId: 'company-a',
      workerIds: <String>['w2'],
      kind: TransferPayloadKind.qualificationsOnly,
      originCompanyId: 'company-c',
      forwardedFromTransferId: 'c-to-b',
    );

    final folders = SubcontractorTransferFolders.group([direct, forwarded]);

    expect(folders, hasLength(1));
    expect(folders.single.originCompanyId, 'company-c');
    expect(folders.single.workerIds, containsAll(<String>['w1', 'w2']));
    expect(folders.single.canForward, isTrue);
  });

  test('different origins stay in separate subcontractor folders', () {
    const fromC = CompanyDataTransfer(
      id: 'c-to-a',
      sourceCompanyId: 'company-c',
      currentCompanyId: 'company-c',
      targetCompanyId: 'company-a',
      workerIds: <String>['w1'],
      kind: TransferPayloadKind.documentsOnly,
    );
    const fromD = CompanyDataTransfer(
      id: 'd-to-a',
      sourceCompanyId: 'company-d',
      currentCompanyId: 'company-d',
      targetCompanyId: 'company-a',
      workerIds: <String>['w2'],
      kind: TransferPayloadKind.documentsOnly,
    );

    final folders = SubcontractorTransferFolders.group([fromC, fromD]);

    expect(folders, hasLength(2));
    expect(
      folders.map((folder) => folder.originCompanyId).toSet(),
      <String>{'company-c', 'company-d'},
    );
  });
}
