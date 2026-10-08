import 'payment_certificate_repository.dart';

/// Materializes only the server's immutable, mutually confirmed document.
/// Values from the editable form are never used to build a certificate.
class SitePaymentAgreementDocument {
  const SitePaymentAgreementDocument._();

  static PaymentCertificateRecord fromSnapshot(Map<String, dynamic> snapshot) {
    final terms = Map<String, dynamic>.from(snapshot['terms'] as Map);
    final mode = terms['mode'];
    if (mode != 'square_meter' && mode != 'lump_sum') {
      throw StateError('支払方式を確認できません。');
    }
    int money(Object? value) {
      if (value is! num || !value.isFinite || value < 0 ||
          value != value.roundToDouble()) {
        throw StateError('保存された金額を確認できません。');
      }
      return value.toInt();
    }

    final base = money(terms['base_amount_yen']);
    final lines = <PaymentCertificateLine>[
      PaymentCertificateLine(
        siteName: snapshot['site_name'].toString(),
        workContent: '${mode == 'square_meter' ? '平米計算' : '請け負い'}'
            '（${terms['tax_included'] == true ? '税込' : '税別'}）',
        quantityLabel: mode == 'square_meter' ? '${terms['area']}㎡' : '一式',
        unitPriceYen: mode == 'square_meter'
            ? money(terms['unit_price_yen'])
            : base,
        amountYen: base,
      ),
    ];
    for (final raw in terms['adjustments'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      if (item['direction'] != 'addition' && item['direction'] != 'deduction') {
        throw StateError('追加項目の加算・控除を確認できません。');
      }
      lines.add(PaymentCertificateLine(
        siteName: '〃',
        workContent: item['name'].toString(),
        quantityLabel: '',
        unitPriceYen: 0,
        amountYen: money(item['amount_yen']) *
            (item['direction'] == 'deduction' ? -1 : 1),
      ));
    }
    if (terms['tax_included'] != true) {
      lines.add(PaymentCertificateLine(
        siteName: '〃',
        workContent: '消費税',
        quantityLabel: '',
        unitPriceYen: 0,
        amountYen: money(terms['tax_amount_yen']),
      ));
    } else {
      lines.add(PaymentCertificateLine(
        siteName: '〃',
        workContent: '消費税（内税${money(terms['tax_amount_yen'])}円）',
        quantityLabel: '',
        unitPriceYen: 0,
        amountYen: 0,
      ));
    }
    final total = money(terms['final_amount_yen']);
    if (lines.fold<int>(0, (sum, line) => sum + line.amountYen) != total) {
      throw StateError('保存された支払明細と総額が一致しません。');
    }
    return PaymentCertificateRecord(
      id: 'agreement:${snapshot['proposal_id']}',
      partnerCompanyName: snapshot['subcontractor_company_name'].toString(),
      payerCompanyName: snapshot['parent_company_name'].toString(),
      // Seal configuration is not yet part of this immutable snapshot contract.
      payerCompanySealEnabled: false,
      periodStart: DateTime.parse(terms['period_start'].toString()),
      periodEnd: DateTime.parse(terms['period_end'].toString()),
      grossAmount: total,
      deductions: 0,
      netAmount: total,
      status: 'draft',
      revision: snapshot['revision'] as int,
      lines: List.unmodifiable(lines),
    );
  }
}
