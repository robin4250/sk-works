/// General insured employees, monthly remuneration, 2026 grade table only.
/// Rates remain company-provided. This lookup does not decide legal eligibility,
/// the remuneration averaging method, statutory revision, or effective month.
/// Sources: Japan Pension Service R08ryougaku.pdf and Kyokai Kenpo R8_13tokyo.pdf.
class PayrollStandardRemuneration {
  const PayrollStandardRemuneration(this.healthYen, this.pensionYen);
  final int healthYen, pensionYen;

  static const healthBases = <int>[
    58000,68000,78000,88000,98000,104000,110000,118000,126000,134000,
    142000,150000,160000,170000,180000,190000,200000,220000,240000,
    260000,280000,300000,320000,340000,360000,380000,410000,440000,
    470000,500000,530000,560000,590000,620000,650000,680000,710000,
    750000,790000,830000,880000,930000,980000,1030000,1090000,1150000,
    1210000,1270000,1330000,1390000,
  ];
  static const lowerBounds = <int>[
    0,63000,73000,83000,93000,101000,107000,114000,122000,130000,
    138000,146000,155000,165000,175000,185000,195000,210000,230000,
    250000,270000,290000,310000,330000,350000,370000,395000,425000,
    455000,485000,515000,545000,575000,605000,635000,665000,695000,
    730000,770000,810000,855000,905000,955000,1005000,1055000,1115000,
    1175000,1235000,1295000,1355000,
  ];

  static PayrollStandardRemuneration fromMonthlyIncome(int income, String month) {
    if (income < 0 || income > 2147483647) {
      throw const FormatException('保険料の基準にする平均月収は0〜2,147,483,647円で入力してください');
    }
    if (!RegExp(r'^2026-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw const FormatException('この等級表は2026年の適用月に対応しています。別の年は通知書の標準報酬月額を入力してください');
    }
    final index = lowerBounds.lastIndexWhere((bound) => income >= bound);
    final health = healthBases[index];
    final pension = health < 88000 ? 88000 : health > 650000 ? 650000 : health;
    return PayrollStandardRemuneration(health, pension);
  }
}
