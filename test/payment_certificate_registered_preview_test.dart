import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';

PartnerPaymentSetting setting(String id, String name) => PartnerPaymentSetting(
  partnerCompanyId: id,
  partnerCompanyName: name,
  dailyRateYen: 25000,
  overtimeHourRateYen: 0,
  earlyHourRateYen: 0,
  nightHourRateYen: 0,
  allowances: const [PaymentAllowanceSetting(name: '交通費', amountYen: 1000)],
);

void main() {
  test('only authorization denial falls back to existing RLS certificates', () {
    for (final error in [
      const PostgrestException(message: 'permission denied', code: '42501'),
      const PostgrestException(message: '管理者のみ操作できます。', code: 'P0001'),
    ]) {
      expect(
        PaymentCertificateRepository.isPreviewPermissionDenied(error),
        isTrue,
      );
    }
    for (final error in [
      const PostgrestException(message: 'unexpected failure', code: 'P0001'),
      const PostgrestException(message: '管理者のみ操作できます。', code: '08006'),
      const PostgrestException(
        message: 'function unavailable',
        code: 'PGRST202',
      ),
    ]) {
      expect(
        PaymentCertificateRepository.isPreviewPermissionDenied(error),
        isFalse,
      );
    }
  });
  final month = DateTime(2026, 10, 8);
  const company = {'name': '株式会社青空工業', 'address': '東京都'};
  test('registered company without attendance has an unsaved zero preview', () {
    final result = PaymentCertificateRepository.withRegisteredCompanyPreviews(
      [],
      [setting('a', '登録会社A')],
      company: company,
      month: month,
    );
    expect(result, hasLength(1));
    final preview = result.single;
    expect(preview.isPreview, isTrue);
    expect(preview.partnerCompanyId, 'a');
    expect(preview.partnerCompanyName, '登録会社A');
    expect(preview.payerCompanyName, '株式会社青空工業');
    expect(preview.periodStart, DateTime(2026, 10, 1));
    expect(preview.periodEnd, DateTime(2026, 10, 31));
    expect(preview.netAmount, 0);
    expect(
      preview.lines.every(
        (line) =>
            line.amountYen == 0 &&
            line.unitPriceYen == 0 &&
            line.quantityLabel.isEmpty,
      ),
      isTrue,
    );
    expect(preview.lines.map((line) => line.workContent), contains('交通費'));
  });

  PaymentCertificateRecord actual(DateTime start) => PaymentCertificateRecord(
    id: 'saved',
    partnerCompanyId: 'a',
    partnerCompanyName: '同じ社名',
    periodStart: start,
    periodEnd: DateTime(start.year, start.month + 1, 0),
    grossAmount: 1000,
    deductions: 0,
    netAmount: 1000,
    status: 'confirmed',
    revision: 1,
  );
  test('unsaved preview follows saved PNG choice without changing a certificate', () {
    final saved = actual(DateTime(2026, 9, 1));
    final result = PaymentCertificateRepository.withRegisteredCompanyPreviews(
      [saved], [setting('a', '登録会社A')],
      company: {
        'id': CompanySealDesign.companyId,
        'name': CompanySealDesign.companyName,
        'company_seal_style': 'png_sumida_v1_worn',
      },
      month: month,
    );
    expect(result.first.companySealSnapshot.style, 'png_sumida_v1_worn');
    expect(result.first.companySealSnapshot.companyId, CompanySealDesign.companyId);
    expect(result.last, same(saved));
    expect(saved.companySealSnapshot, same(CompanySealSnapshot.legacy));
  });

  test('preview preserves selected font and rejects another company PNG', () {
    expect(CompanySealSnapshot.forPreview({
      'name': '株式会社青空工業', 'company_seal_style': 'aoyagi_reisho',
    }).style, 'aoyagi_reisho');
    expect(() => CompanySealSnapshot.forPreview({
      'id': 'another-company', 'name': CompanySealDesign.companyName,
      'company_seal_style': 'png_sumida_v1_standard',
    }), throwsStateError);
  });

  test('dedupe uses partner id and preserves the actual certificate', () {
    final saved = actual(DateTime(2026, 10, 1));
    final result = PaymentCertificateRepository.withRegisteredCompanyPreviews(
      [saved],
      [setting('a', '同じ社名'), setting('b', '同じ社名')],
      company: company,
      month: month,
    );
    expect(result, hasLength(2));
    expect(result.where((item) => item.isPreview).single.partnerCompanyId, 'b');
    expect(result.last, same(saved));
    expect(saved.netAmount, 1000);
  });
  test('older certificate does not suppress current month preview', () {
    final saved = actual(DateTime(2026, 9, 1));
    final result = PaymentCertificateRepository.withRegisteredCompanyPreviews(
      [saved],
      [setting('a', '同じ社名')],
      company: company,
      month: month,
    );
    expect(result, hasLength(2));
    expect(result.first.isPreview, isTrue);
    expect(result.last, same(saved));
  });
}
