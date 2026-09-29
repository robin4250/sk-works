/// Public/discoverable identifiers used to find a company before requesting
/// an SKO company connection.
///
/// Corporate number is a public identifier in Japan. SKO company ID is an
/// application identifier. Search results still require an explicit connection
/// request and acceptance; finding a company never grants data access.
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

  bool get hasQuery => <String?>[
        companyName,
        address,
        corporateNumber,
        skoCompanyId,
      ].any((value) => value != null && value!.trim().isNotEmpty);
}
