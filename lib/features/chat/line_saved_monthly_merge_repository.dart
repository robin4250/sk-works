import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import '../auth/secondary_reset_session_guard.dart';
import 'line_import_repository.dart';

/// A session-bound adapter for the existing invoice draft RPCs. It never moves
/// original messages, enables LINE, submits attendance or creates invoices.
class LineSavedMonthlyMergeRepository extends ChangeNotifier {
  LineSavedMonthlyMergeRepository.forClient(this._client) {
    _session = _client.auth.currentSession;
    _actor = _session?.user.id;
    _owner = AppAuthMutationGateway.forClient(_client);
    _admission = _owner.externalFlowAdmission();
    _guard = SecondaryResetSessionGuard(
      currentSession: () => _client.auth.currentSession,
      changes: _client.auth.onAuthStateChange,
      onInvalidated: _invalidate,
    );
    _quarantine = _owner.logoutQuarantine.changes.listen((state) {
      if (state != AppLogoutQuarantineState.clear) _invalidate();
    }, onError: (Object _) => _invalidate(), onDone: _invalidate);
    var first = true;
    _events = _client.auth.onAuthStateChange.listen((event) {
      final replay = first && identical(event.session, _session);
      first = false;
      if (event.event == AuthChangeEvent.signedIn && !replay) _invalidate();
    }, onError: (Object _) => _invalidate(), onDone: _invalidate);
  }

  static LineSavedMonthlyMergeRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
          ? LineSavedMonthlyMergeRepository.forClient(SupabaseBackend.client)
          : null;

  final SupabaseClient _client;
  late final Session? _session;
  late final String? _actor;
  late final AppAuthMutationGateway _owner;
  late final Future<int?> _admission;
  late final SecondaryResetSessionGuard _guard;
  StreamSubscription<AuthState>? _events;
  StreamSubscription<AppLogoutQuarantineState>? _quarantine;
  int? _epoch;
  String? _company, _target, _source, _pendingSource, _pendingPayload;
  int _pairGeneration = 0;
  final _loadedMonths = <String, String>{};
  final _preparedCommands = <String, String>{};
  bool _invalid = false, _closed = false, _writing = false;

  bool get isCurrent => !_closed && !_invalid && _guard.isCurrent &&
      _session?.isExpired == false && _epoch != null &&
      _owner.isExternalFlowCurrent(_epoch!);

  static bool _uuid(Object? value) => value is String &&
      RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(value);

  void _invalidate() {
    if (_closed || _invalid) return;
    _invalid = true;
    notifyListeners();
  }

  Future<void> _check() async {
    final epoch = await _admission;
    _epoch ??= epoch;
    if (epoch == null || !_owner.isExternalFlowCurrent(epoch)) _invalidate();
    await _guard.checkAfterQueuedEvents();
    if (!isCurrent) {
      _invalidate();
      throw StateError('ログイン状態が変わりました。画面を開き直してください。');
    }
  }

  String _month(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-01';

  bool _sameJson(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _sameJson(a[i], b[i]));
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _sameJson(a[key], b[key]));
    }
    return a == b;
  }

  Future<String> _scope(String group) async {
    await _check();
    if (!_uuid(group)) {
      throw StateError('グループを確認してください。');
    }
    final rows = await _client.from('communication_groups').select('id,company_id')
        .eq('id', group).limit(2)
        .setHeader('Authorization', 'Bearer ${_session!.accessToken}')
        .timeout(const Duration(seconds: 30));
    await _check();
    if (rows.length != 1 || rows.single['id'] != group ||
        !_uuid(rows.single['company_id'])) {
      throw StateError('グループの会社を確認できません。');
    }
    final company = rows.single['company_id'] as String;
    if (_company != null && _company != company) {
      throw StateError('同じ会社の保存済みデータを選択してください。');
    }
    final members = await _client.from('company_members').select('company_id,user_id,role')
        .eq('company_id', company).eq('user_id', _actor!).limit(2)
        .setHeader('Authorization', 'Bearer ${_session.accessToken}')
        .timeout(const Duration(seconds: 30));
    await _check();
    if (members.length != 1 || members.single['company_id'] != company ||
        members.single['user_id'] != _actor ||
        !const ['owner', 'admin', 'manager'].contains(members.single['role'])) {
      throw StateError('現在の会社・管理権限を確認できません。');
    }
    // Concurrent first loads must not adopt different companies.
    if (_company != null && _company != company) {
      throw StateError('会社が変わりました。画面を開き直してください。');
    }
    _company ??= company;
    return company;
  }

  Future<Object?> _rpc(String name, Map<String, dynamic> params) async {
    await _check();
    final result = await _client.rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${_session!.accessToken}')
        .timeout(const Duration(seconds: 30));
    await _check();
    return result;
  }

  Future<List<Map<String, dynamic>>> destinations() async {
    final result = await _rpc('line_history_destinations', const {});
    if (result is! List || result.any((v) => v is! Map ||
        !_uuid(v['id']) || v['name'] is! String)) {
      throw StateError('保存済みグループを確認できません。');
    }
    final rows = result.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    if (rows.map((v) => v['id']).toSet().length != rows.length) {
      throw StateError('保存済みグループを一意に確認できません。');
    }
    return rows;
  }

  Map<String, dynamic> _workspace(Object? result) {
    if (result is! Map || result['revision'] is! int || result['revision'] < 0 ||
        result['can_edit'] != true || result['candidate_rows'] is! List ||
        result['source_messages'] is! List ||
        !LineImportFeatures.fromJson(result['features']).invoice) {
      throw StateError('保存済みデータの権限・設定・保存版を確認できません。');
    }
    final workspace = Map<String, dynamic>.from(jsonDecode(jsonEncode(result)) as Map);
    final kind = workspace['source_kind'];
    if (!const ['received', 'history', 'mixed'].contains(kind)) {
      throw StateError('元の投稿種別を確認できません。');
    }
    final sources = <Map<String, dynamic>>[];
    for (final raw in workspace['source_messages'] as List) {
      if (raw is! Map) throw StateError('元の投稿を確認できません。');
      final source = Map<String, dynamic>.from(raw);
      if (source['source_type'] == null) {
        if (kind == 'mixed') throw StateError('混在する投稿の出所を確認できません。');
        source['source_type'] = kind;
      }
      if (!const ['received', 'history'].contains(source['source_type'])) {
        throw StateError('元の投稿種別を確認できません。');
      }
      sources.add(source);
    }
    workspace['source_messages'] = sources;
    if ((workspace['candidate_rows'] as List).any((row) => row is! Map)) {
      throw StateError('保存済みの候補行を確認できません。');
    }
    return workspace;
  }

  Future<Map<String, dynamic>> load(String group, DateTime month) async {
    await _scope(group);
    final result = _workspace(await _rpc('line_import_workspace', {
      'p_group_id': group, 'p_target': 'invoice', 'p_month': _month(month),
    }));
    await _scope(group);
    _loadedMonths[group] = _month(month);
    return result;
  }

  Future<void> verifyGroups(String targetGroup, String sourceGroup) async {
    if (targetGroup == sourceGroup || (_target != null && _target != targetGroup) ||
        ((_writing || _pendingPayload != null) && (_pendingSource ?? _source) != sourceGroup)) {
      throw StateError('まとめ先と追加元を確認してください。');
    }
    final generation = ++_pairGeneration;
    if (_source != sourceGroup && _pendingPayload == null) _preparedCommands.clear();
    _source = null;
    final company = await _scope(targetGroup);
    if (await _scope(sourceGroup) != company) throw StateError('別会社のデータは追加できません。');
    await _scope(targetGroup);
    // Recheck after awaits: another verification cannot replace this binding.
    if (generation != _pairGeneration || (_target != null && _target != targetGroup)) {
      throw StateError('追加対象が変わりました。画面を開き直してください。');
    }
    _target = targetGroup;
    _source = sourceGroup;
  }

  Map<String, dynamic> saveCommand({required String groupId, required String target,
    required DateTime month, required int revision, required String sourceKind,
    required List<Map<String, dynamic>> sources, required List<Map<String, dynamic>> rows,
    required String note, required bool confirmed}) {
    if (target != 'invoice' || confirmed) throw StateError('月別参考データだけを保存できます。');
    if (_target != groupId || _source == null ||
        _loadedMonths[groupId] != _month(month) || _loadedMonths[_source] != _month(month)) {
      throw StateError('まとめ先・追加元の同じ年月を確認してください。');
    }
    final command = LineImportRepository(_client).saveCommand(groupId: groupId, target: target,
      month: month, revision: revision, sourceKind: sourceKind, sources: sources,
      rows: rows, note: note, confirmed: confirmed);
    _preparedCommands[command['p_command_id'] as String] = jsonEncode(command);
    return command;
  }

  Future<Map<String, dynamic>> save(Map<String, dynamic> command) async {
    if (_writing) throw StateError('保存結果を確認しています。');
    final captured = Map<String, dynamic>.from(jsonDecode(jsonEncode(command)) as Map);
    final month = DateTime.tryParse(captured['p_month']?.toString() ?? '');
    final source = _pendingSource ?? _source;
    if (_target == null || source == null || captured['p_group_id'] != _target ||
        captured['p_target'] != 'invoice' || captured['p_confirmed'] != false ||
        _loadedMonths[_target] != captured['p_month'] || _loadedMonths[source] != captured['p_month'] ||
        !_uuid(captured['p_command_id']) || month == null || _month(month) != captured['p_month'] ||
        captured['p_expected_revision'] is! int || captured['p_expected_revision'] < 0 ||
        captured['p_sources'] is! List || captured['p_rows'] is! List) {
      throw StateError('選択したまとめ先・年月・保存内容を確認してください。');
    }
    final payload = jsonEncode(captured);
    if (_preparedCommands[captured['p_command_id']] != payload) {
      throw StateError('確認した追加内容から保存してください。');
    }
    if (_pendingPayload != null && _pendingPayload != payload) {
      throw StateError('前回の保存結果が未確認です。同じ保存内容で確認してください。');
    }
    _writing = true;
    try {
      await verifyGroups(_target!, source);
      // The existing RPC repeats permissions/feature checks and revision CAS.
      // Do not replace a source payload after an uncertain write acknowledgement.
      _pendingPayload = payload;
      _pendingSource = source;
      Object? saved;
      try {
        saved = await _rpc('save_line_import_draft', captured);
      } on PostgrestException catch (error) {
        // These are server rejections of this RPC transaction. A later scope
        // read failure must not take this path: the save may already exist.
        if (const ['22023', '40001', '42501'].contains(error.code)) {
          _pendingPayload = null;
          _pendingSource = null;
          _preparedCommands.remove(captured['p_command_id']);
        }
        rethrow;
      }
      final result = _workspace(saved);
      if (!_uuid(result['draft_id']) || result['revision'] != captured['p_expected_revision'] + 1 ||
          result['source_kind'] != captured['p_source_kind'] || result['confirmed'] != false ||
          result['note_comparison'] != captured['p_note'] ||
          !_sameJson(result['source_messages'], captured['p_sources']) ||
          !_sameJson(result['candidate_rows'], captured['p_rows'])) {
        throw StateError('保存結果が追加内容と一致しません。結果を確認してください。');
      }
      await verifyGroups(_target!, source);
      _pendingPayload = null;
      _pendingSource = null;
      return result;
    } finally {
      _writing = false;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _quarantine?.cancel();
    await _events?.cancel();
    await _guard.close();
    super.dispose();
  }
}
