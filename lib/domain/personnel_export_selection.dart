import 'company_data_transfer.dart';

class PersonnelExportSelection {
  const PersonnelExportSelection({
    required this.workerIds,
    required this.kind,
  });

  final List<String> workerIds;
  final TransferPayloadKind kind;

  bool get isEmpty => workerIds.isEmpty;

  String get summaryLabel => switch (kind) {
        TransferPayloadKind.personnelBundle => '基本情報＋資格＋書類',
        TransferPayloadKind.qualificationsOnly => '資格',
        TransferPayloadKind.documentsOnly => '書類',
      };

  bool get supportsMultiSelect => true;
}
