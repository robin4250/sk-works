import 'company_data_transfer.dart';

class SubcontractorTransferFolder {
  const SubcontractorTransferFolder({
    required this.originCompanyId,
    required this.transfers,
  });

  final String originCompanyId;
  final List<CompanyDataTransfer> transfers;

  bool get isEmpty => transfers.isEmpty;

  List<String> get workerIds {
    final ids = <String>{};
    for (final transfer in transfers) {
      ids.addAll(transfer.workerIds);
    }
    return List<String>.unmodifiable(ids);
  }

  bool get canForward => transfers.isNotEmpty;
}

class SubcontractorTransferFolders {
  const SubcontractorTransferFolders._();

  static List<SubcontractorTransferFolder> group(
    Iterable<CompanyDataTransfer> transfers,
  ) {
    final grouped = <String, List<CompanyDataTransfer>>{};

    for (final transfer in transfers) {
      final origin = transfer.originCompanyId ?? transfer.sourceCompanyId;
      grouped.putIfAbsent(origin, () => <CompanyDataTransfer>[]).add(transfer);
    }

    return grouped.entries
        .map(
          (entry) => SubcontractorTransferFolder(
            originCompanyId: entry.key,
            transfers: List<CompanyDataTransfer>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }
}
