import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_position_transfer.dart';

void main() {
  Map<String, dynamic> snapshot(String type) => {
    'version': 1, 'enabled': true, 'pay_type': type,
    'items': [{'name': '役職手当', 'amount_yen': 11000}],
  };
  final earnings = <String, Object?>{'基本給': 200000, '役職手当': 11000, '残業手当': 25000};
  test('known monthly/hourly snapshots are valid but never transfer any money', () {
    for (final type in ['monthly', 'hourly']) {
      final detail = <String, dynamic>{'position_transfer_snapshot': snapshot(type)};
      final before = jsonEncode(detail), moneyBefore = jsonEncode(earnings);
      expect(validNonDailyPayrollPositionTransferSnapshot(detail), isTrue);
      expect(payrollPositionTransfer(detail, earnings), isNull);
      expect(jsonEncode(detail), before);
      expect(jsonEncode(earnings), moneyBefore);
    }
  });
  test('malformed and unknown requested snapshots cannot suppress warnings', () {
    final invalid = <Map<String, dynamic>>[
      {...snapshot('monthly'), 'version': 2},
      {...snapshot('monthly'), 'pay_type': 'future'},
      {...snapshot('monthly'), 'items': null},
      {...snapshot('monthly'), 'items': []},
      {...snapshot('monthly'), 'items': [{'name': '', 'amount_yen': 11000}]},
      {...snapshot('monthly'), 'items': [{'name': '基本給', 'amount_yen': 11000}]},
      {...snapshot('monthly'), 'items': [{'name': '基本給の調整額', 'amount_yen': 11000}]},
      {...snapshot('monthly'), 'items': [{'name': '役職手当', 'amount_yen': 0}]},
      {...snapshot('monthly'), 'items': [{'name': '役職手当', 'amount_yen': -1}]},
      {...snapshot('monthly'), 'items': [{'name': '役職手当', 'amount_yen': 1.5}]},
      {...snapshot('monthly'), 'items': [{'name': '役職手当', 'amount_yen': '11000'}]},
      {...snapshot('monthly'), 'items': [{'name': '役職手当', 'amount_yen': 2147483648}]},
      {...snapshot('monthly'), 'items': [
        {'name': '役職手当', 'amount_yen': 11000}, {'name': ' 役職手当 ', 'amount_yen': 1}]},
      {...snapshot('monthly'), 'items': [
        {'name': '役職手当', 'amount_yen': 2147483647}, {'name': '勤務手当', 'amount_yen': 1}]},
      {...snapshot('monthly'), 'extra': true},
    ];
    for (final snap in invalid) {
      final detail = <String, dynamic>{'position_transfer_snapshot': snap};
      expect(validNonDailyPayrollPositionTransferSnapshot(detail), isFalse, reason: '$snap');
      expect(payrollPositionTransfer(detail, earnings), isNull);
    }
    expect(validNonDailyPayrollPositionTransferSnapshot({}), isFalse);
    expect(validNonDailyPayrollPositionTransferSnapshot({'position_transfer_snapshot': snapshot('daily')}), isFalse);
    expect(validNonDailyPayrollPositionTransferSnapshot({'position_transfer_snapshot': {
      ...snapshot('monthly'), 'enabled': false}}), isFalse);
  });
  test('daily validation shares the same item bounds and retains saved evidence checks', () {
    final daily = <String, dynamic>{'position_transfer_snapshot': snapshot('daily'),
      'attendance_unit_evidence': {'contract_version': 1, 'items': [
        {'name': '基本給', 'section': 'earning', 'category': 'day', 'unit': 'day',
          'rate_yen': 10000, 'quantity': 20, 'amount_yen': 200000}]}};
    expect(payrollPositionTransfer(daily, earnings), isNotNull);
    expect(payrollPositionTransfer(daily, {...earnings, '役職手当': 9999}), isNull);
    final snap = daily['position_transfer_snapshot'] as Map;
    snap['items'] = [{'name': '基本給', 'amount_yen': 200000}];
    expect(payrollPositionTransfer(daily, earnings), isNull);
  });
}
