/// Immutable, company-bound PNG designs approved by the company owner.
/// Never replace bytes for an existing style ID: issue a new version instead.
class CompanySealDesign {
  const CompanySealDesign._();
  static const companyId = '0f117273-0a06-4a2f-85ec-720a3c9f4cf4';
  static const companyName = 'すみだ建設株式会社';
  static const designs = {
    'png_sumida_v1_standard': (
      label: '① 標準（採用案）',
      asset: 'assets/images/company-seals/sumida-v1/standard.png',
      sha256:
          '612e6c684b684ecb5f84230e79a5accad3e1a1e52a19470e5deae53ee478bbd1',
    ),
    'png_sumida_v1_light': (
      label: '② すっきり',
      asset: 'assets/images/company-seals/sumida-v1/light.png',
      sha256:
          '9a92a7eddcff164a871f0fb663febe381f2bb8076e2a232e220211bf0a38e8ba',
    ),
    'png_sumida_v1_worn': (
      label: '③ かすれ',
      asset: 'assets/images/company-seals/sumida-v1/worn.png',
      sha256:
          '071cb3b850ade006c3c8a99c07a3af1dc193caac04ac001d1436303f182373cf',
    ),
  };
  static bool isPng(String style) => designs.containsKey(style);
  static bool matches(String? id, String name) =>
      id == companyId && name == companyName;
  static bool supported(String style) =>
      style == 'legacy' || style == 'aoyagi_reisho' || isPng(style);
}
