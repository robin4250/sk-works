class ProductModule {
  const ProductModule({
    required this.key,
    required this.label,
    required this.description,
    this.core = false,
  });

  final String key;
  final String label;
  final String description;
  final bool core;
}

class ProductModules {
  const ProductModules._();

  static const people = ProductModule(
    key: 'people',
    label: '社員・協力会社',
    description: '社員・協力会社・作業員の基本情報',
    core: true,
  );

  static const settings = ProductModule(
    key: 'settings',
    label: '設定',
    description: '会社情報・共通設定',
    core: true,
  );

  static const optional = <ProductModule>[
    ProductModule(
      key: 'qualifications',
      label: '資格管理',
      description: '資格マスター・保有資格・資格証',
    ),
    ProductModule(
      key: 'documents',
      label: '必要書類',
      description: '社員・作業員の必要書類チェック',
    ),
    ProductModule(
      key: 'attendance',
      label: '勤怠・人工',
      description: '勤怠・出退勤確認・人工',
    ),
    ProductModule(
      key: 'sites',
      label: '現場管理',
      description: '現場・店舗・プロジェクト管理',
    ),
    ProductModule(
      key: 'chat',
      label: 'チャット',
      description: '会社・現場グループのチャット',
    ),
    ProductModule(
      key: 'notes',
      label: 'ノート',
      description: '会社・現場グループのノート',
    ),
    ProductModule(
      key: 'albums',
      label: 'アルバム',
      description: '会社・現場グループの写真管理',
    ),
    ProductModule(
      key: 'invoices',
      label: '請求管理',
      description: '請求計算・請求書',
    ),
    ProductModule(
      key: 'line_bridge',
      label: 'LINE連携',
      description: 'LINEグループ連携・出勤候補',
    ),
  ];

  static final byKey = <String, ProductModule>{
    people.key: people,
    settings.key: settings,
    for (final module in optional) module.key: module,
  };
}
