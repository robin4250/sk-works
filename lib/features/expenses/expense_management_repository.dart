import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'expense_claim.dart';

class ExpenseReviewCommand {
  ExpenseReviewCommand(
    this.id,
    this.actor,
    this.company,
    this.claim,
    this.revision,
    this.action,
    this.destination,
  );
  factory ExpenseReviewCommand.create(
    String actor,
    String company,
    String claim,
    int revision,
    String action,
    ExpenseAllocation? destination,
  ) {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ExpenseReviewCommand(
      '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}',
      actor,
      company,
      claim,
      revision,
      action,
      destination,
    );
  }
  final String id, actor, company, claim, action;
  final int revision;
  final ExpenseAllocation? destination;
  Map<String, dynamic> get params => {
    'p_command_id': id,
    'p_claim': claim,
    'p_revision': revision,
    'p_action': action,
    'p_allocation': destination?.category.name,
    'p_counterparty': destination?.counterpartyId,
  };
  String get encoded =>
      jsonEncode({'actor': actor, 'company': company, ...params});
  factory ExpenseReviewCommand.decode(String text) {
    final v = jsonDecode(text) as Map<String, dynamic>;
    for (final k in ['actor', 'company', 'p_command_id', 'p_claim']) {
      if (v[k] is! String || (v[k] as String).isEmpty) {
        throw StateError('保留操作を確認できません。');
      }
    }
    if (v['p_revision'] is! int ||
        v['p_revision'] < 1 ||
        !['approve', 'reject', 'allocate'].contains(v['p_action'])) {
      throw StateError('保留操作を確認できません。');
    }
    final d = v['p_allocation'] == null
        ? null
        : ExpenseAllocation(
            ExpenseCategory.values.byName(v['p_allocation']),
            counterpartyId: v['p_counterparty'],
          );
    if ((v['p_action'] == 'allocate') != (d != null) ||
        d?.category == ExpenseCategory.unallocated ||
        (d == null && v['p_counterparty'] != null)) {
      throw StateError('保留操作を確認できません。');
    }
    return ExpenseReviewCommand(
      v['p_command_id'],
      v['actor'],
      v['company'],
      v['p_claim'],
      v['p_revision'],
      v['p_action'],
      d,
    );
  }
}

class ExpenseReviewWorkspace {
  ExpenseReviewWorkspace(
    Map<String, dynamic> data,
    String company,
    DateTime month,
  ) {
    if (data['company_id'] != company) throw StateError('会社が一致しません。');
    canReview = data['can_review'] == true;
    canConfigure = data['can_configure'] == true;
    settingsRevision = data['settings_revision'] as int;
    approvers = List<String>.from(data['approver_ids']);
    candidates = (data['candidates'] as List)
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    final entries = <ExpenseClaim>[];
    for (final v in data['claims'] as List) {
      final r = Map<String, dynamic>.from(v);
      final date = DateTime.parse(r['incurred_on']);
      if (r['company_id'] != company ||
          date.year != month.year ||
          date.month != month.month ||
          r['revision'] is! int) {
        throw StateError('申請の対象が一致しません。');
      }
      revisions[r['id']] = r['revision'];
      actors[r['id']] = r['created_by'];
      entries.add(
        ExpenseClaim(
          id: r['id'],
          companyId: company,
          applicantId: r['applicant_id'],
          applicantName: r['applicant_name'],
          incurredOn: date,
          submittedAt: DateTime.parse(r['submitted_at']),
          description: r['description'],
          amountYen: r['amount_yen'],
          approval: ExpenseApproval.values.byName(r['approval']),
          allocation: ExpenseAllocation(
            ExpenseCategory.values.byName(r['allocation']),
            counterpartyId: r['counterparty_id'],
            counterpartyName: r['counterparty_name'],
          ),
        ),
      );
    }
    claims = ExpenseClaims(companyId: company, claims: entries);
    destinations = (data['destinations'] as List)
        .map(
          (r) => ExpenseAllocation(
            ExpenseCategory.values.byName(r['category']),
            counterpartyId: r['id'],
            counterpartyName: r['name'],
          ),
        )
        .toList();
  }
  late final ExpenseClaims claims;
  late final bool canReview, canConfigure;
  late final int settingsRevision;
  late final List<String> approvers;
  late final List<Map<String, dynamic>> candidates;
  late final List<ExpenseAllocation> destinations;
  final revisions = <String, int>{};
  final actors = <String, String>{};
  bool canDecide(ExpenseClaim claim, String actor) =>
      canReview && (approvers.length == 1 || actors[claim.id] != actor);
}

abstract class ExpenseManagementAccess {
  String? get actor;
  Future<List<Map<String, dynamic>>> companies();
  Future<ExpenseReviewWorkspace> load(String company, DateTime month);
  Future<ExpenseReviewCommand?> pending(String company);
  Future<void> execute(ExpenseReviewCommand command);
  Future<void> configure(String company, List<String> users, int revision);
}

typedef ExpenseRpc =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

class ExpenseManagementRepository implements ExpenseManagementAccess {
  ExpenseManagementRepository({String? Function()? actor, ExpenseRpc? rpc})
    : _actor = actor ?? (() => SupabaseBackend.client.auth.currentUser?.id),
      _rpc =
          rpc ??
          ((name, params) => SupabaseBackend.client.rpc(name, params: params));
  final String? Function() _actor;
  final ExpenseRpc _rpc;
  @override
  String? get actor => _actor();
  void _check(String? expected) {
    if (expected == null || actor != expected) {
      throw StateError('ログイン情報が変わりました。');
    }
  }

  Future<dynamic> _read(String name, Map<String, dynamic> p) async {
    final expected = actor;
    _check(expected);
    final result = await _rpc(name, p);
    _check(expected);
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> companies() async =>
      ((await _read('expense_management_companies', {})) as List)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
  @override
  Future<ExpenseReviewWorkspace> load(
    String company,
    DateTime month,
  ) async => ExpenseReviewWorkspace(
    Map<String, dynamic>.from(
      await _read('expense_review_workspace', {
        'p_company': company,
        'p_month':
            '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
      }),
    ),
    company,
    month,
  );
  String _key(String actor, String company) =>
      'sko.expense.review.v1.$actor.$company';
  @override
  Future<ExpenseReviewCommand?> pending(String company) async {
    final expected = actor;
    _check(expected);
    final prefs = await SharedPreferences.getInstance();
    _check(expected);
    final text = prefs.getString(_key(expected!, company));
    if (text == null) return null;
    final c = ExpenseReviewCommand.decode(text);
    if (c.actor != expected || c.company != company) {
      throw StateError('保留操作の対象が一致しません。');
    }
    return c;
  }

  static final _running = <String, Future<void>>{};
  @override
  Future<void> execute(ExpenseReviewCommand command) async {
    _check(command.actor);
    final key = _key(command.actor, command.company);
    if (_running.containsKey(key)) throw StateError('経費の操作を確認中です。');
    final future = _execute(command, key);
    _running[key] = future;
    try {
      await future;
    } finally {
      if (identical(_running[key], future)) _running.remove(key);
    }
  }

  Future<void> _execute(ExpenseReviewCommand c, String key) async {
    // Validate even programmatically-created commands before persisting.
    ExpenseReviewCommand.decode(c.encoded);
    final prefs = await SharedPreferences.getInstance();
    _check(c.actor);
    final previous = prefs.getString(key);
    if (previous != null && previous != c.encoded) {
      throw StateError('先に保留操作を確認してください。');
    }
    if (!await prefs.setString(key, c.encoded)) {
      throw StateError('操作を端末に保存できません。');
    }
    _check(c.actor);
    try {
      final result = Map<String, dynamic>.from(
        await _rpc('expense_review_command', c.params),
      );
      _check(c.actor);
      if (result['id'] != c.claim ||
          result['company_id'] != c.company ||
          result['revision'] is! int ||
          result['revision'] < c.revision) {
        throw StateError('操作結果が一致しません。');
      }
      if (!await prefs.remove(key)) throw StateError('操作結果を再確認してください。');
    } on PostgrestException catch (e) {
      // SQL rejects the transaction: safe to reload before a new command.
      if (['40001', '42501', '22023', 'P0001'].contains(e.code)) {
        _check(c.actor);
        await prefs.remove(key);
      }
      rethrow;
    }
  }

  @override
  Future<void> configure(
    String company,
    List<String> users,
    int revision,
  ) async {
    if (users.isEmpty ||
        users.length > 3 ||
        users.toSet().length != users.length) {
      throw StateError('承認担当を1〜3名選択してください。');
    }
    await _read('set_expense_approvers', {
      'p_company': company,
      'p_users': users,
      'p_revision': revision,
    });
  }
}
