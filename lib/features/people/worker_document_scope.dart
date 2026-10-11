bool workerDocumentMatchesScope(Object? scope, String selected) =>
    selected == 'all' ||
    scope == selected ||
    (scope == 'both' && (selected == 'internal' || selected == 'upstream'));

String workerDocumentScopeLabel(Object? scope) => switch (scope) {
  'both' => '自社・取引会社で共用（登録は1回）',
  'upstream' => '取引会社提出',
  _ => '自社用',
};
