import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/supabase_backend.dart';
import 'company_payroll_rates_repository.dart';

abstract class PayrollRatePendingStore {
  Future<PayrollRatePendingWrite?> read(String companyId);
  Future<void> write(PayrollRatePendingWrite pending);
  Future<void> clear(PayrollRatePendingWrite expected);
}

/// Flushes recovery records before the RPC is sent; one actor/company owns each file.
class FilePayrollRatePendingStore implements PayrollRatePendingStore {
  FilePayrollRatePendingStore({String? Function()? actorId,
    Future<Directory> Function()? directory})
      : _actorId = actorId ?? (() => SupabaseBackend.client.auth.currentUser?.id),
        _directory = directory ?? getApplicationSupportDirectory;
  final String? Function() _actorId;
  final Future<Directory> Function() _directory;
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
    return jsonEncode([actor, companyId]);
  }

  Future<File> _file(String key) async {
    final root = await _directory();
    final folder = Directory('${root.path}/payroll-rate-pending-v1');
    await folder.create(recursive: true);
    return File('${folder.path}/${sha256.convert(utf8.encode(key))}.json');
  }

  @override
  Future<PayrollRatePendingWrite?> read(String companyId) async {
    final key = _key(companyId);
    return _locked(key, () async {
      final file = await _file(key);
      if (key != _key(companyId)) throw StateError('料率設定の利用者が変わりました');
      if (!await file.exists()) return null;
      final value = payrollRateObject(jsonDecode(await file.readAsString()));
      if (key != _key(companyId)) throw StateError('料率設定の利用者が変わりました');
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
      final file = await _file(key);
      if (key != _key(pending.companyId)) throw StateError('料率設定の利用者が変わりました');
      if (await file.exists()) throw StateError('先の保存結果を確認してください');
      await file.writeAsString(jsonEncode(_value(pending)), flush: true);
      if (key != _key(pending.companyId)) throw StateError('料率設定の利用者が変わりました');
    });
  }

  @override
  Future<void> clear(PayrollRatePendingWrite expected) async {
    final companyId = expected.companyId;
    final key = _key(companyId);
    return _locked(key, () async {
      final file = await _file(key);
      if (!await file.exists()) throw StateError('確認対象の保存結果がありません');
      final raw = jsonDecode(await file.readAsString());
      if (key != _key(companyId) || !payrollRateValuesEqual(raw, _value(expected))) {
        throw StateError('確認対象の保存結果が変わりました');
      }
      await file.delete();
    });
  }
}
