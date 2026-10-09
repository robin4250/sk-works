import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/supabase_backend.dart';
import 'company_payroll_rates_repository.dart';

abstract class PayrollRatePendingStore {
  Future<PayrollRatePendingWrite?> read(String companyId);
  Future<void> write(PayrollRatePendingWrite pending);
  Future<void> clear(PayrollRatePendingWrite expected);
}

/// Recovery records belong to the current actor and company, including after restart.
class SharedPreferencesPayrollRatePendingStore implements PayrollRatePendingStore {
  SharedPreferencesPayrollRatePendingStore({String? Function()? actorId})
      : _actorId = actorId ?? (() => SupabaseBackend.client.auth.currentUser?.id);
  final String? Function() _actorId;
  String? _boundActor;
  static final Map<String, Future<void>> _locks = {};

  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final previous = _locks[key] ?? Future<void>.value();
    final completed = Completer<void>();
    final current = completed.future;
    _locks[key] = current;
    await previous;
    try {
      return await action();
    } finally {
      completed.complete();
      if (identical(_locks[key], current)) _locks.remove(key);
    }
  }

  Map<String, dynamic> _value(PayrollRatePendingWrite pending) => {
    'company_id': pending.companyId, 'expected_version': pending.expectedVersion,
    'value': pending.value, 'item_id': pending.itemId, 'origin': pending.origin,
  };

  String _key(String companyId) {
    final actor = _actorId();
    if (actor == null || actor.isEmpty) throw StateError('料率設定の利用者を確認できません');
    _boundActor ??= actor;
    if (_boundActor != actor) throw StateError('料率設定の利用者が変わりました');
    return 'payroll-rate-pending-v1:${jsonEncode([actor, companyId])}';
  }

  @override
  Future<PayrollRatePendingWrite?> read(String companyId) async {
    final key = _key(companyId);
    return _locked(key, () async {
    final preferences = await SharedPreferences.getInstance();
    if (key != _key(companyId)) throw StateError('料率設定の利用者が変わりました');
    await preferences.reload();
    if (key != _key(companyId)) throw StateError('料率設定の利用者が変わりました');
    final raw = preferences.getString(key);
    if (raw == null) return null;
    final value = payrollRateObject(jsonDecode(raw));
    if (value['company_id'] != companyId || value['expected_version'] is! int ||
        (value['expected_version'] as int) < 0 ||
        (value['item_id'] != null && value['item_id'] is! String) ||
        (value['origin'] != null && value['origin'] is! String)) {
      throw const FormatException('保存結果の確認情報を読み込めません');
    }
    return PayrollRatePendingWrite(companyId: companyId,
      expectedVersion: value['expected_version'] as int,
      value: payrollRateObject(value['value']), itemId: value['item_id'] as String?,
      origin: value['origin'] as String?);
    });
  }

  @override
  Future<void> write(PayrollRatePendingWrite pending) async {
    final key = _key(pending.companyId);
    return _locked(key, () async {
    final preferences = await SharedPreferences.getInstance();
    if (key != _key(pending.companyId)) throw StateError('料率設定の利用者が変わりました');
    await preferences.reload();
    if (preferences.getString(key) != null) throw StateError('先の保存結果を確認してください');
    final saved = await preferences.setString(key, jsonEncode(_value(pending)));
    if (!saved || key != _key(pending.companyId)) throw StateError('保存結果の確認情報を保持できません');
    });
  }

  @override
  Future<void> clear(PayrollRatePendingWrite expected) async {
    final companyId = expected.companyId;
    final key = _key(companyId);
    return _locked(key, () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final raw = preferences.getString(key);
      if (key != _key(companyId) || raw == null ||
          !payrollRateValuesEqual(jsonDecode(raw), _value(expected))) {
        throw StateError('確認対象の保存結果が変わりました');
      }
      if (!await preferences.remove(key)) throw StateError('保存結果の確認情報を更新できません');
    });
  }
}
