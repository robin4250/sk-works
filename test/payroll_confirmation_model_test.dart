import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_confirmation_repository.dart';

void main() {
  test('month-end close disallows payment before confirmation opens', () {
    expect(
      () => PayrollConfirmationRepository.validatePaymentPolicy(
        paymentDay: 25,
        paymentMonthOffset: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => PayrollConfirmationRepository.validatePaymentPolicy(
        paymentDay: 31,
        paymentMonthOffset: 0,
      ),
      returnsNormally,
    );
    expect(
      () => PayrollConfirmationRepository.validatePaymentPolicy(
        paymentDay: 25,
        paymentMonthOffset: 1,
      ),
      returnsNormally,
    );
  });

  test('server permission is required even for an admin candidate', () {
    final settings = PayrollConfirmationSettings.fromJson({}, [
      {
        'user_id': 'admin',
        'display_name': '管理者',
        'role': 'admin',
        'selected_position': 1,
      },
    ]);
    expect(settings.canManageSettings, isFalse);
    expect(settings.reviewerUserIds, ['admin']);
  });
  test(
    'selected reviewers preserve server order without unselected candidates',
    () {
      final settings = PayrollConfirmationSettings.fromJson(
        {
          'payment_day': 25,
          'payment_month_offset': 1,
          'closing_day': 31,
          'can_manage_settings': true,
        },
        [
          {
            'user_id': 'viewer',
            'display_name': '閲覧者',
            'role': 'viewer',
            'selected_position': 2,
          },
          {'user_id': 'unused', 'display_name': '未選択', 'role': 'manager'},
          {
            'user_id': 'admin',
            'display_name': '管理者',
            'role': 'admin',
            'selected_position': 1,
          },
        ],
      );
      expect(settings.canManageSettings, isTrue);
      expect(settings.reviewerUserIds, ['admin', 'viewer']);
      expect(settings.paymentMonthOffset, 1);
    },
  );
  test('pending or malformed timestamps cannot create a PDF stamp', () {
    final status = PayrollConfirmationStatus.fromJson({
      'period_start': '2026-10-01',
      'confirmation_open_date': '2026-10-31',
      'payday': '2026-11-25',
      'can_confirm': false,
      'confirmed': false,
      'reviewers': [
        {
          'user_id': 'a',
          'name': '確認済',
          'position': 1,
          'confirmed': true,
          'confirmed_at': '2026-10-31T10:00:00+09:00',
        },
        {
          'user_id': 'b',
          'name': '取消済',
          'position': 2,
          'confirmed': false,
          'confirmed_at': '2026-10-31T09:00:00+09:00',
        },
        {
          'user_id': 'c',
          'name': '未確認',
          'position': 3,
          'confirmed': true,
          'confirmed_at': 'invalid',
        },
      ],
    });
    expect(status.requiredCount, 3);
    expect(status.confirmedCount, 1);
    expect(status.canConfirm, isFalse);
    expect(status.canCancel, isFalse);
    expect(
      status.reviewers[0].confirmedAt!.toUtc(),
      DateTime.utc(2026, 10, 31, 1),
    );
    final stamps = status.pdfDetail['payroll_confirmations'] as List;
    expect(stamps[1]['confirmed_at'], isNull);
    expect(stamps[2]['confirmed_at'], isNull);
    expect(status.pdfDetail['payment_date'], '2026-11-25');
  });
  test('missing status cannot fabricate a date or grant confirmation', () {
    final status = PayrollConfirmationStatus.fromJson({});
    expect(status.periodStart, isNull);
    expect(status.payday, isNull);
    expect(status.canConfirm, isFalse);
    expect(status.confirmed, isFalse);
    expect(status.pdfDetail.containsKey('payment_date'), isFalse);
    expect(status.confirmedCount, 0);
  });
}
