enum SiteContractConfirmationMode { legacy, sealed, unknown }

SiteContractConfirmationMode siteContractConfirmationMode(Object? workspace) {
  if (workspace is! Map || workspace['proposals'] is! List) {
    return SiteContractConfirmationMode.unknown;
  }
  final proposals = workspace['proposals'] as List;
  if (proposals.any((row) => row is! Map || row['seals'] is! List)) {
    return SiteContractConfirmationMode.unknown;
  }
  return proposals.any((row) => (row['seals'] as List).isNotEmpty)
      ? SiteContractConfirmationMode.sealed : SiteContractConfirmationMode.legacy;
}
