/// Wage policy for newly calculated paid leave. Saved statements are never
/// recalculated by this helper; their recorded amounts remain authoritative.
class PaidLeavePay {
  const PaidLeavePay({required this.dailyAmountYen, required this.addToWages});

  final int dailyAmountYen;
  final bool addToWages;

  factory PaidLeavePay.fromSettings(Map<String, dynamic> settings) {
    int money(Object? value) {
      final number = value is num ? value : num.tryParse('$value');
      if (number == null || !number.isFinite || number < 0) return 0;
      return number.round();
    }

    final type = settings['pay_type']?.toString() ?? 'daily';
    if (type == 'monthly') {
      return PaidLeavePay(
        dailyAmountYen: money(settings['calculation_daily_base_yen']),
        addToWages: false,
      );
    }
    if (type == 'hourly') {
      final formula = settings['rate_formula'];
      final override = formula is Map ? formula['paid_leave_daily_yen'] : null;
      return PaidLeavePay(
        dailyAmountYen: override == null
            ? money((settings['hourly_rate_yen'] is num
                ? settings['hourly_rate_yen'] as num
                : num.tryParse('${settings['hourly_rate_yen']}') ?? 0) * 8)
            : money(override),
        addToWages: true,
      );
    }
    return PaidLeavePay(
      dailyAmountYen: money(settings['day_daily']),
      addToWages: true,
    );
  }

  int additionalWagesForDays(int approvedDays) {
    if (approvedDays < 0) throw ArgumentError.value(approvedDays);
    return addToWages ? dailyAmountYen * approvedDays : 0;
  }
}
