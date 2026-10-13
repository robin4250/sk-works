import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'expense_receipt_attachment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../data/supabase_backend.dart';
import 'expense_claim.dart';
import 'expense_settlement_choice.dart';

class ExpenseSubmission {
  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  ExpenseSubmission({
    required this.id,
    required this.actor,
    required this.company,
    required this.worker,
    required this.date,
    required this.description,
    required this.amount,
    this.receipt,
  });
  factory ExpenseSubmission.create(
    String actor,
    String company,
    String worker,
    DateTime date,
    String description,
    String amount, {
    ExpenseReceiptAttachment? receipt,
  }) {
    final yen = int.tryParse(amount);
    if (!RegExp(r'^[0-9]+$').hasMatch(amount) ||
        yen == null ||
        yen < 1 ||
        yen > 999999999) {
      throw StateError('金額は1〜999999999円の整数で入力してください。');
    }
    if (description.trim().isEmpty || description.trim().length > 1000) {
      throw StateError('内容は1〜1000文字で入力してください。');
    }
    return ExpenseSubmission(
      id: _uuid(),
      actor: actor,
      company: company,
      worker: worker,
      date:
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      description: description.trim(),
      amount: yen, receipt: receipt,
    );
  }
  factory ExpenseSubmission.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) throw StateError('保留申請の形式を確認できません。');
    final v = decoded;
    for (final key in [
      'id',
      'actor',
      'company',
      'worker',
      'date',
      'description',
    ]) {
      if (v[key] is! String || (v[key] as String).trim().isEmpty) {
        throw StateError('保留申請の形式を確認できません。');
      }
    }
    final date = DateTime.tryParse(v['date']);
    if (date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v['date']) ||
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' !=
            v['date'] ||
        v['amount'] is! int ||
        v['amount'] < 1 ||
        v['amount'] > 999999999 ||
        (v['description'] as String).length > 1000) {
      throw StateError('保留申請の形式を確認できません。');
    }
    return ExpenseSubmission(
      id: v['id'],
      actor: v['actor'],
      company: v['company'],
      worker: v['worker'],
      date: v['date'],
      description: v['description'],
      amount: v['amount'],
      receipt: v['receipt'] == null ? null : ExpenseReceiptAttachment.decode(Map<String, dynamic>.from(v['receipt'])),
    );
  }
  final String id, actor, company, worker, date, description;
  final int amount;
  final ExpenseReceiptAttachment? receipt;
  String get encoded => jsonEncode({
    'id': id,
    'actor': actor,
    'company': company,
    'worker': worker,
    'date': date,
    'description': description,
    'amount': amount,
    if (receipt != null) 'receipt': receipt!.encoded,
  });
  void verify(Map<String, dynamic> row) {
    if (row['id'] != id ||
        row['created_by'] != actor ||
        row['company_id'] != company ||
        row['applicant_id'] != worker ||
        row['incurred_on'] != date ||
        row['description'] != description ||
        row['amount_yen'] != amount ||
        (receipt != null && row['receipt_object_path'] != receipt!.objectPath(company, actor, id))) {
      throw StateError('申請の照会結果が一致しません。同じ申請の確認が必要です。');
    }
  }
}

abstract class ExpenseSubmissionAccess {
  String? get actor;
  Future<List<Map<String, dynamic>>> scopes();
  Future<List<ExpenseClaim>> history(
    String company,
    String worker,
    DateTime month,
  );
  Future<ExpenseSubmission?> pending(String company, String worker);
  Future<void> submit(ExpenseSubmission draft);
}

class ExpenseSubmissionRepository implements ExpenseSubmissionAccess {
  final _client = SupabaseBackend.client;
  @override
  String? get actor => _client.auth.currentUser?.id;
  void _check(String? expected) {
    if (expected == null || actor != expected) {
      throw StateError('ログイン情報が変わりました。開き直してください。');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> scopes() async {
    final expected = actor;
    _check(expected);
    final rows = await _client.rpc('expense_personal_scopes');
    _check(expected);
    return (rows as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<List<ExpenseClaim>> history(
    String company,
    String worker,
    DateTime month,
  ) async {
    final expected = actor;
    _check(expected);
    dynamic rows;
    final params = {
      'p_company': company, 'p_worker': worker,
      'p_month': '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
    };
    try { rows = await _client.rpc('expense_personal_receipt_history', params: params); }
    on PostgrestException catch (error) {
      if (error.code != 'PGRST202') rethrow;
      rows = await _client.rpc('expense_personal_settlement_history', params: params);
    }
    _check(expected);
    return (rows as List).map((v) {
      final r = Map<String, dynamic>.from(v);
      if (r['company_id'] != company ||
          r['applicant_id'] != worker ||
          r['created_by'] != expected) {
        throw StateError('申請者が一致しません。');
      }
      return ExpenseClaim(
        id: r['id'],
        companyId: company,
        applicantId: worker,
        applicantName: r['applicant_name'],
        incurredOn: DateTime.parse(r['incurred_on']),
        submittedAt: DateTime.parse(r['submitted_at']),
        receiptObjectPath: r['receipt_object_path'],
        reviewedAt: r['reviewed_at'] == null ? null : DateTime.parse(r['reviewed_at']),
        reviewedBy: r['reviewed_by'], reviewedByName: r['reviewed_by_name'], reviewMemo: r['review_memo'],
        description: r['description'],
        amountYen: r['amount_yen'],
        approval: ExpenseApproval.values.byName(r['approval']),
        revision: r['revision'] as int? ?? 1,
        withdrawn: r['withdrawn'] == true,
        settlement: r['settlement_method'] == null && r['settlement_month'] == null
          ? null : ExpenseSettlementChoice.decode(r['settlement_method'], r['settlement_month']),
        allocation: ExpenseAllocation(
          ExpenseCategory.values.byName(r['allocation']),
          counterpartyId: r['counterparty_id'],
          counterpartyName: r['counterparty_name'],
        ),
      );
    }).toList();
  }

  Future<Map<String, dynamic>> reviewHistory(ExpenseClaim claim) async {
    final expected = actor;
    _check(expected);
    final data = Map<String, dynamic>.from(await _client.rpc('expense_review_flow_history', params: {'p_claim': claim.id}));
    _check(expected);
    if (data['claim_id'] != claim.id || data['company_id'] != claim.companyId || data['events'] is! List) throw StateError('履歴の対象が一致しません。');
    return data;
  }

  String _key(String expected, String company, String worker) =>
      'sko.expense.pending.v1.$expected.$company.$worker';
  @override
  Future<ExpenseSubmission?> pending(String company, String worker) async {
    final expected = actor;
    _check(expected);
    final prefs = await SharedPreferences.getInstance();
    _check(expected);
    final encoded = prefs.getString(_key(expected!, company, worker));
    if (encoded == null) return null;
    final d = ExpenseSubmission.decode(encoded);
    if (d.actor != expected || d.company != company || d.worker != worker) {
      throw StateError('保留申請の対象が一致しません。');
    }
    return d;
  }

  static final _inFlight = <String, (String, Future<void>)>{};
  @override
  Future<void> submit(ExpenseSubmission draft) {
    final key = _key(draft.actor, draft.company, draft.worker);
    final running = _inFlight[key];
    if (running != null) {
      if (running.$1 != draft.encoded) {
        return Future.error(StateError('申請の送信確認中です。'));
      }
      return running.$2;
    }
    final task = _submit(draft);
    final guarded = task.whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = (draft.encoded, guarded);
    return guarded;
  }

  Future<void> _uploadReceipt(ExpenseSubmission draft) async {
    final photo = draft.receipt!;
    final expectedPath = photo.objectPath(draft.company, draft.actor, draft.id);
    Future<Map<String, dynamic>> prepare() async {
      _check(draft.actor);
      final data = Map<String, dynamic>.from(await _client.rpc('expense_prepare_receipt', params: {
        'p_claim': draft.id, 'p_company': draft.company, 'p_worker': draft.worker,
        'p_sha256': photo.sha256Hex, 'p_size': photo.size, 'p_mime': photo.mime,
      }));
      _check(draft.actor);
      if (data['claim_id'] != draft.id || data['object_path'] != expectedPath) throw StateError('領収書の保存先が一致しません。');
      return data;
    }
    final reservation = await prepare();
    final bucket = _client.storage.from('expense-receipts');
    if (reservation['uploaded'] != true) {
      final bytes = await photo.verifiedBytes();
      _check(draft.actor);
      try {
        await bucket.uploadBinary(expectedPath, bytes, fileOptions: FileOptions(contentType: photo.mime, upsert: false));
      } on StorageException {
        final retried = await prepare();
        if (retried['uploaded'] != true) rethrow;
      }
    }
    _check(draft.actor);
    final uploaded = await bucket.download(expectedPath);
    _check(draft.actor);
    if (uploaded.length != photo.size || sha256.convert(uploaded).toString() != photo.sha256Hex) {
      throw StateError('領収書の保存内容が一致しません。');
    }
  }

  Future<void> _submit(ExpenseSubmission draft) async {
    _check(draft.actor);
    final prefs = await SharedPreferences.getInstance();
    _check(draft.actor);
    final key = _key(draft.actor, draft.company, draft.worker);
    final previous = prefs.getString(key);
    if (previous != null && previous != draft.encoded) {
      throw StateError('保留申請を先に確認してください。');
    }
    if (!await prefs.setString(key, draft.encoded)) {
      throw StateError('再送用の申請を保存できません。');
    }
    _check(draft.actor);
    // A failed lookup must never turn into a new submission.
    var row = await _client.rpc(
      draft.receipt == null ? 'expense_personal_exact' : 'expense_personal_exact_with_receipt',
      params: {'p_id': draft.id},
    );
    _check(draft.actor);
    if (row == null && draft.receipt != null) await _uploadReceipt(draft);
    row ??= await _client.rpc(
      draft.receipt == null ? 'expense_personal_submit' : 'expense_personal_submit_with_receipt',
      params: {
        'p_id': draft.id,
        'p_company': draft.company,
        'p_worker': draft.worker,
        'p_date': draft.date,
        'p_description': draft.description,
        'p_amount': draft.amount,
      },
    );
    _check(draft.actor);
    draft.verify(Map<String, dynamic>.from(row));
    if (!await prefs.remove(key)) throw StateError('保存済みです。再確認してください。');
  }
}
