import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'payroll_unit_item_editor.dart';

class PayrollUnitConditions {
  const PayrollUnitConditions({
    required this.version,
    required this.month,
    required this.canEdit,
    required this.items,
  });
  final int version;
  final String month;
  final bool canEdit;
  final List<PayrollUnitItemDraft> items;
  factory PayrollUnitConditions.fromJson(Object? raw) {
    if (raw is! Map ||
        raw['version'] is! int ||
        raw['month'] is! String ||
        raw['items'] is! List) {
      throw StateError('Payroll unit response unavailable');
    }
    final items = <PayrollUnitItemDraft>[];
    for (final value in raw['items'] as List) {
      if (value is! Map ||
          value['id'] is! String ||
          value['name'] is! String ||
          value['rate_yen'] is! num) {
        throw StateError('Payroll unit response unavailable');
      }
      final section = PayrollItemSection.values
          .where((x) => x.name == value['section'])
          .firstOrNull;
      final unit = PayrollItemUnit.values
          .where((x) => x.name == value['unit'])
          .firstOrNull;
      if (section == null || unit == null) {
        throw StateError('Payroll unit response unavailable');
      }
      final rate = value['rate_yen'] as num;
      if (!rate.isFinite ||
          rate < 0 ||
          rate > 2147483647 ||
          rate != rate.round()) {
        throw StateError('Payroll unit response unavailable');
      }
      items.add(
        PayrollUnitItemDraft(
          id: value['id'] as String,
          section: section,
          unit: unit,
          name: value['name'] as String,
          rate: (value['rate_yen'] as num).toStringAsFixed(0),
          source: value['source']?.toString() ?? 'manual_hours',
          quantity: value['quantity']?.toString() ?? '',
        ),
      );
    }
    return PayrollUnitConditions(
      version: raw['version'] as int,
      month: raw['month'] as String,
      canEdit: raw['can_edit'] == true,
      items: List.unmodifiable(items),
    );
  }
}

class PayrollUnitConditionsRepository {
  PayrollUnitConditionsRepository(SupabaseClient client)
    : _client = client,
      _actor = (() => client.auth.currentUser?.id);
  @visibleForTesting
  PayrollUnitConditionsRepository.forTesting(this._client, this._actor);
  final SupabaseClient _client;
  final String? Function() _actor;
  Future<bool> available() async {
    try {
      return await _client.rpc('payroll_unit_conditions_contract_version') == 1;
    } catch (_) {
      return false;
    }
  }

  Future<PayrollUnitConditions> load(
    String companyId,
    String workerId,
    String month,
  ) async {
    final actor = _actor();
    if (actor == null) throw StateError('Session unavailable');
    final raw = await _client.rpc(
      'payroll_unit_conditions',
      params: {
        'p_company_id': companyId,
        'p_worker_id': workerId,
        'p_month': month,
      },
    );
    if (_actor() != actor) {
      throw StateError('Session changed');
    }
    final value = PayrollUnitConditions.fromJson(raw);
    if (value.month != month) throw StateError('Payroll month changed');
    return value;
  }

  Future<PayrollUnitConditions> save(
    String companyId,
    String workerId,
    PayrollUnitConditions current,
    List<PayrollUnitItemDraft> items,
  ) async {
    final actor = _actor();
    if (actor == null || !current.canEdit) {
      throw StateError('Payroll edit unavailable');
    }
    final raw = await _client.rpc(
      'save_payroll_unit_conditions',
      params: {
        'p_company_id': companyId,
        'p_worker_id': workerId,
        'p_month': current.month,
        'p_expected_version': current.version,
        'p_items': [
          for (final item in items)
            {
              'id': item.id.startsWith('new-unit-item-') ? null : item.id,
              'section': item.section.name,
              'unit': item.unit.name,
              'name': item.name,
              'rate_yen': int.parse(item.rate),
              'source': item.source,
              'quantity': item.quantity.isEmpty ? null : item.quantity,
            },
        ],
      },
    );
    if (_actor() != actor) {
      throw StateError('Session changed');
    }
    final value = PayrollUnitConditions.fromJson(raw);
    if (value.month != current.month) throw StateError('Payroll month changed');
    return value;
  }
}
