import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'expense_claim.dart';
import 'expense_submission_repository.dart';

class ExpensePersonalChange {
  ExpensePersonalChange(this.actor, this.company, this.worker, Map<String, dynamic> parameters)
    : parameters = Map.unmodifiable(parameters);
  factory ExpensePersonalChange.create(
    String actor,
    ExpenseClaim claim, {
    ExpenseSubmission? edit,
  }) {
    if (claim.withdrawn) throw StateError('取り下げ済みです。');
    final token =
        edit ??
        ExpenseSubmission.create(
          actor,
          claim.companyId,
          claim.applicantId,
          claim.incurredOn,
          claim.description,
          '${claim.amountYen}',
        );
    return ExpensePersonalChange(actor, claim.companyId, claim.applicantId, {
      'p_command_id': token.id,
      'p_claim': claim.id,
      'p_revision': claim.revision,
      'p_action': edit == null ? 'withdraw' : 'edit',
      'p_date': edit?.date,
      'p_description': edit?.description,
      'p_amount': edit?.amount,
    });
  }
  final String actor, company, worker;
  final Map<String, dynamic> parameters;
  bool get withdrawing => parameters['p_action'] == 'withdraw';
  String get encoded => jsonEncode({
    'actor': actor,
    'company': company,
    'worker': worker,
    'parameters': parameters,
  });
  factory ExpensePersonalChange.decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map ||
        raw['actor'] is! String ||
        raw['company'] is! String ||
        raw['worker'] is! String ||
        raw['parameters'] is! Map) {
      throw StateError('変更の確認情報を読み込めません。');
    }
    final parameters = Map<String, dynamic>.from(raw['parameters']);
    if (parameters['p_command_id'] is! String ||
        parameters['p_claim'] is! String ||
        parameters['p_revision'] is! int ||
        parameters['p_revision'] < 1 ||
        !['edit', 'withdraw'].contains(parameters['p_action'])) {
      throw StateError('変更の確認情報を読み込めません。');
    }
    return ExpensePersonalChange(
      raw['actor'],
      raw['company'],
      raw['worker'],
      parameters,
    );
  }
  void verify(dynamic raw) {
    if (raw is! Map ||
        raw['id'] != parameters['p_claim'] ||
        raw['company_id'] != company ||
        raw['applicant_id'] != worker ||
        raw['created_by'] != actor ||
        raw['revision'] != parameters['p_revision'] + 1 ||
        raw['allocation'] != 'unallocated' ||
        raw['counterparty_id'] != null ||
        (withdrawing
            ? raw['withdrawn'] != true || raw['approval'] != 'rejected'
            : raw['withdrawn'] == true ||
                  raw['approval'] != 'pending' ||
                  raw['incurred_on'] != parameters['p_date'] ||
                  raw['description'] != parameters['p_description'] ||
                  raw['amount_yen'] != parameters['p_amount'])) {
      throw StateError('変更結果を確認できません。同じ変更を再確認してください。');
    }
  }
}

abstract class ExpensePersonalChangeAccess {
  Future<ExpensePersonalChange?> pending(String company, String worker);
  Future<void> send(ExpensePersonalChange command);
}

class ExpensePersonalChangeRepository implements ExpensePersonalChangeAccess {
  ExpensePersonalChangeRepository({
    String? Function()? actor,
    Future<dynamic> Function(Map<String, dynamic>)? invoke,
  }) : _actor = actor ?? (() => SupabaseBackend.client.auth.currentUser?.id),
       _invoke =
           invoke ??
           ((params) => SupabaseBackend.client.rpc(
             'expense_personal_change',
             params: params,
           ));
  final String? Function() _actor;
  final Future<dynamic> Function(Map<String, dynamic>) _invoke;
  static final _running = <String, (String, Future<void>)>{};
  String _key(String actor, String company, String worker) =>
      'sko.expense.change.v1.$actor.$company.$worker';
  void _check(String actor) {
    if (_actor() != actor) throw StateError('ログイン情報が変わりました。');
  }

  @override
  Future<ExpensePersonalChange?> pending(String company, String worker) async {
    final actor = _actor();
    if (actor == null) throw StateError('ログインが必要です。');
    final prefs = await SharedPreferences.getInstance();
    _check(actor);
    final encoded = prefs.getString(_key(actor, company, worker));
    if (encoded == null) return null;
    final command = ExpensePersonalChange.decode(encoded);
    if (command.actor != actor ||
        command.company != company ||
        command.worker != worker) {
      throw StateError('変更対象が一致しません。');
    }
    return command;
  }

  @override
  Future<void> send(ExpensePersonalChange command) {
    final key = _key(command.actor, command.company, command.worker);
    final running = _running[key];
    if (running != null) {
      if (running.$1 != command.encoded) {
        return Future.error(StateError('確認中の変更があります。'));
      }
      return running.$2;
    }
    final task = _send(command).whenComplete(() => _running.remove(key));
    _running[key] = (command.encoded, task);
    return task;
  }

  Future<void> _send(ExpensePersonalChange command) async {
    _check(command.actor);
    final prefs = await SharedPreferences.getInstance();
    _check(command.actor);
    final key = _key(command.actor, command.company, command.worker);
    final previous = prefs.getString(key);
    if (previous != null && previous != command.encoded) {
      throw StateError('確認中の変更があります。');
    }
    if (!await prefs.setString(key, command.encoded)) {
      throw StateError('変更の確認情報を保存できません。');
    }
    _check(command.actor);
    try {
      final raw = await _invoke(command.parameters);
      _check(command.actor);
      command.verify(raw);
    } on PostgrestException catch (error) {
      _check(command.actor);
      if (const {'40001', '42501', '22023', '23505'}.contains(error.code)) {
        await prefs.remove(key);
        throw StateError('申請が変更されたか、操作できません。履歴を再読み込みしてください。');
      }
      rethrow;
    }
    if (!await prefs.remove(key)) throw StateError('保存済みです。同じ変更を再確認してください。');
  }
}
