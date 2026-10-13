class ProductBrand {
  const ProductBrand._();

  static const displayName = 'SKO';
  static const tagline = '会社・現場・人員・資格・勤怠・請求をひとつに。';

  // Keep operator/legal naming separate from the user-facing product brand.
  // This can be replaced later without touching persistence keys, package IDs,
  // backend identifiers, or other compatibility-sensitive names.
  static const operatorName = 'SKO Japan';
}
