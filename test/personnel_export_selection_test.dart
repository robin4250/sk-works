import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_data_transfer.dart';
import 'package:sk_works/domain/personnel_export_selection.dart';

void main() {
  test('personnel list selects the full information bundle', () {
    const selection = PersonnelExportSelection(
      workerIds: <String>['a', 'b'],
      kind: TransferPayloadKind.personnelBundle,
    );
    expect(selection.summaryLabel, '基本情報＋資格＋書類');
    expect(selection.supportsMultiSelect, isTrue);
  });

  test('qualification and document pages keep scoped exports', () {
    const qualifications = PersonnelExportSelection(
      workerIds: <String>['a'],
      kind: TransferPayloadKind.qualificationsOnly,
    );
    const documents = PersonnelExportSelection(
      workerIds: <String>['a'],
      kind: TransferPayloadKind.documentsOnly,
    );
    expect(qualifications.summaryLabel, '資格');
    expect(documents.summaryLabel, '書類');
  });
}
