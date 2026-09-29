class CompanySearchKey {
  const CompanySearchKey({
    this.companyName,
    this.address,
    this.corporateNumber,
    this.skoCompanyId,
  });

  final String? companyName;
  final String? address;
  final String? corporateNumber;
  final String? skoCompanyId;

  bool get hasQuery {
    for (final value in <String?>[
      companyName,
      address,
      corporateNumber,
      skoCompanyId,
    ]) {
      if (value?.trim().isNotEmpty == true) return true;
    }
    return false;
  }
}
