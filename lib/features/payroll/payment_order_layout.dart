/// Image bytes and hidden snapshot metadata must never shrink order text.
bool paymentOrderUsesCompactLayout(Map<String, dynamic> payload) {
  const fields = [
    'month',
    'intro_text',
    'work_name',
    'work_address',
    'period_start',
    'period_end',
    'payment_conditions',
    'notes',
    'issue_date',
    'total_amount_yen',
    'tax_amount_yen',
  ];
  var length = 0;
  for (final key in fields) {
    length += payload[key]?.toString().length ?? 0;
  }
  for (final key in ['issuer', 'counterparty']) {
    final party = payload[key];
    if (party is Map) {
      for (final field in [
        'name',
        'address',
        'corporate_number',
        'representative_name',
      ]) {
        length += party[field]?.toString().length ?? 0;
      }
    }
  }
  final bank=payload['counterparty_bank'];
  if(bank is Map){for(final field in ['bank_name','branch_name','account_type','account_number','account_holder']){length+=bank[field]?.toString().length??0;}}
  return length > 1800;
}
