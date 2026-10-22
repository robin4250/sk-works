import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'payroll_unit_item_editor.dart';
import 'company_common_calculation_resolution.dart';

class PayrollUnitConditions {
  const PayrollUnitConditions({
    required this.version,
    required this.month,
    required this.canEdit,
    required this.items,
    this.companyCommonItems = const [],
    this.companyCommonSourceJson,
    this.companyCommonHistoryMissing = false,
    this.companyCommonFrozen = false,
    this.companyCommonResolution,
  });
  final int version;
  final String month;
  final bool canEdit;
  final List<PayrollUnitItemDraft> items;
  final List<Map<String, dynamic>> companyCommonItems;
  final String? companyCommonSourceJson;
  final bool companyCommonHistoryMissing;
  final bool companyCommonFrozen;
  final CompanyCommonCalculationResolution? companyCommonResolution;
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
    final common = raw['company_common'];
    final commonItems = <Map<String, dynamic>>[];
    String? commonSource;
    if (common != null) {
      if (common is! Map || common['contract_version'] != 1 ||
          common['source'] is! Map || common['items'] is! List ||
          common['history_missing'] != null && common['history_missing'] is! bool ||
          common['frozen'] != null && common['frozen'] is! bool) {
        throw StateError('Company common response unavailable');
      }
      final ids = <String>{};
      for (final entry in common['items'] as List) {
        if (entry is! Map || entry['id'] is! String ||
            !ids.add(entry['id'] as String) || entry['name'] is! String ||
            !['earning', 'deduction'].contains(entry['section']) ||
            !['hour', 'day', 'month'].contains(entry['unit']) ||
            entry['rate_yen'] is! int || (entry['rate_yen'] as int) < 0 ||
            entry['quantity'] != null && (entry['quantity'] is! num ||
                !(entry['quantity'] as num).isFinite || (entry['quantity'] as num) < 0) ||
            entry['amount_yen'] != null && (entry['amount_yen'] is! int ||
                (entry['amount_yen'] as int) < 0) ||
            entry['quantity_month'] != raw['month']) {
          throw StateError('Company common item unavailable');
        }
        commonItems.add(Map.unmodifiable(Map<String, dynamic>.from(entry)));
      }
      commonSource = jsonEncode(common['source']);
    }
    return PayrollUnitConditions(
      version: raw['version'] as int,
      month: raw['month'] as String,
      canEdit: raw['can_edit'] == true,
      items: List.unmodifiable(items),
      companyCommonItems: List.unmodifiable(commonItems),
      companyCommonSourceJson: commonSource,
      companyCommonHistoryMissing: common is Map && common['history_missing'] == true,
      companyCommonFrozen: common is Map && common['frozen'] == true,
      companyCommonResolution: common is Map && common['resolution'] != null
          ? CompanyCommonCalculationResolution.parse(common['resolution']) : null,
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

  Future<PayrollUnitConditions> saveCommonHours(
    String companyId,
    String workerId,
    PayrollUnitConditions current,
    Map<String, String> hours,
  ) async {
    final actor = _actor();
    if (actor == null || !current.canEdit || current.companyCommonSourceJson == null || hours.isEmpty) {
      throw StateError('Company common edit unavailable');
    }
    final known = current.companyCommonItems.where((x) => x['unit'] == 'hour').map((x) => x['id']).toSet();
    for (final entry in hours.entries) {
      if (!known.contains(entry.key) || !RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(entry.value) ||
          num.parse(entry.value) > 99999999) {
        throw const FormatException('時間数を0以上の数値で入力してください');
      }
    }
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Session unavailable');
    var revoked = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.accessToken != token || event.session?.user.id != actor) revoked = true;
    }, onError: (Object _) { revoked = true; });
    try {
    final raw = await _client.rpc('save_payroll_common_hours', params: {
      'p_company_id': companyId, 'p_worker_id': workerId,
      'p_month': current.month, 'p_expected_source': jsonDecode(current.companyCommonSourceJson!),
      'p_hours': [for (final entry in hours.entries) {'id': entry.key, 'quantity': entry.value}],
    }).setHeader('Authorization', 'Bearer $token');
    if (revoked || _actor() != actor || _client.auth.currentSession?.accessToken != token) throw StateError('Session changed');
    final value = PayrollUnitConditions.fromJson(raw);
    if (value.month != current.month) throw StateError('Payroll month changed');
    return value;
    } finally { await subscription.cancel(); }
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

