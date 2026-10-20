/// Receipt metadata only. A count is never inferred from timeline or item length.
class CommonPayrollPublicationSummary {
  const CommonPayrollPublicationSummary({this.recalculatedScopes});
  final int? recalculatedScopes;

  factory CommonPayrollPublicationSummary.fromReceipt(Object? raw) {
    final count = raw is Map ? raw['recalculated_scopes'] : null;
    return CommonPayrollPublicationSummary(
      recalculatedScopes: count is int && count >= 0 ? count : null,
    );
  }

  String get message =>
      '適用月を登録しました。'
      '${recalculatedScopes == null ? '再計算件数を確認できません。' : '給与下書きの再計算：$recalculatedScopes件。'}'
      '未入力の時間数がある給与は計算保留です。';
}
