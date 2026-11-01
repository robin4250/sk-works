import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import 'worker_document_photos.dart';
import 'worker_document_change_repository.dart';
import 'worker_document_admin_correction_repository.dart';

class WorkerDocumentRepository {
  WorkerDocumentRepository._(this._client);

  @visibleForTesting
  WorkerDocumentRepository.forTesting(this._client);

  final SupabaseClient _client;
  WorkerDocumentChangeRepository createChangeRepository() => WorkerDocumentChangeRepository(_client);
  Future<WorkerDocumentAdminCorrectionRepository> createAdminCorrectionRepository({
    required String companyId,
    required String targetId,
    required bool Function() isCurrentTarget,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!isCurrentTarget()) {
      throw StateError('ログイン・会社・書類の状態が変わりました。');
    }
    return WorkerDocumentAdminCorrectionRepository(
      client: _client,
      companyId: companyId,
      targetId: targetId,
      preferences: preferences,
      isCurrentTarget: isCurrentTarget,
    );
  }
  String? get actorId => _client.auth.currentUser?.id;
  Future<List<String>> pendingAdminCorrectionTargets(String companyId) async {
    final actor = actorId;
    final current = await captureAttachmentReadScope();
    final preferences = await SharedPreferences.getInstance();
    if (actor == null || actorId != actor || !current()) {
      throw StateError('ログイン状態が変わりました。');
    }
    return WorkerDocumentAdminCorrectionRepository.pendingTargets(preferences, actor, companyId);
  }
  Stream<AuthState> get attachmentAuthChanges => _client.auth.onAuthStateChange;
  Future<bool Function()> captureAttachmentReadScope() async {
    final session = _client.auth.currentSession;
    final actor = _client.auth.currentUser?.id;
    final gateway = AppAuthMutationGateway.forClient(_client);
    final epoch = await gateway.externalFlowAdmission();
    if (session == null || actor == null || session.isExpired || epoch == null ||
        !identical(session, _client.auth.currentSession)) { throw StateError('Attachment session changed'); }
    return () => !session.isExpired && identical(session, _client.auth.currentSession) &&
      _client.auth.currentUser?.id == actor && gateway.isExternalFlowCurrent(epoch);
  }

  static const _bucket = 'worker-documents';

  static WorkerDocumentRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return WorkerDocumentRepository._(client);
  }

  static const defaultRequirements = <Map<String, Object>>[
    {'name': '履歴書', 'scope': 'internal', 'expiry': false},
    {'name': '住民票', 'scope': 'internal', 'expiry': false},
    {'name': 'マイナンバーカード', 'scope': 'internal', 'expiry': true},
    {'name': '身元保証書', 'scope': 'internal', 'expiry': false},
    {'name': '社員登録票', 'scope': 'internal', 'expiry': false},
    {'name': '通勤届', 'scope': 'internal', 'expiry': false},
    {'name': '賃金の口座振込同意書', 'scope': 'internal', 'expiry': false},
    {'name': '入社連絡票', 'scope': 'internal', 'expiry': false},
    {'name': '年金手帳', 'scope': 'internal', 'expiry': false},
    {'name': '雇用保険被保険者証', 'scope': 'internal', 'expiry': false},
    {'name': '就業規則同意書', 'scope': 'internal', 'expiry': false},
    {'name': '未成年就業同意書', 'scope': 'internal', 'expiry': false},
    {'name': '運転免許証', 'scope': 'internal', 'expiry': true},
    {'name': '資格証', 'scope': 'upstream', 'expiry': true},
    {'name': '健康診断書', 'scope': 'upstream', 'expiry': true},
    {'name': '雇用契約書', 'scope': 'internal', 'expiry': false},
    {'name': '誓約書', 'scope': 'internal', 'expiry': false},
    {'name': '銀行口座情報', 'scope': 'internal', 'expiry': false},
    {'name': '自由項目1', 'scope': 'internal', 'expiry': false},
    {'name': '自由項目2', 'scope': 'internal', 'expiry': false},
  ];

  Future<({String companyId, String role})> membership() async {
    final session = _client.auth.currentSession;
    final current = await captureAttachmentReadScope();
    final user = _client.auth.currentUser;
    if (user == null || session == null || !current() ||
        !identical(session, _client.auth.currentSession)) {
      throw StateError('SKOへのログインが必要です。');
    }
    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(2)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!current() || !identical(session, _client.auth.currentSession)) {
      throw StateError('ログイン情報が変更されました。画面を開き直してください。');
    }
    if (rows.isEmpty) { throw StateError('会社情報が見つかりません。'); }
    if (rows.length != 1 || rows.single['company_id'] is! String ||
        (rows.single['company_id'] as String).isEmpty) {
      throw StateError('所属会社が複数あるため処理できません。');
    }
    return (
      companyId: rows.single['company_id'] as String,
      role: rows.single['role']?.toString() ?? 'viewer',
    );
  }

  Future<bool> canManageRequirements() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
  }

  Future<bool> canManageStatuses() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
  }

  Future<void> _requireManagePeople() async {
    if (!await canManageStatuses()) {
      throw StateError('必要書類を変更する権限がありません。');
    }
  }

  Future<String> _companyId() async => (await membership()).companyId;

  bool _photoSchemaAvailable = true;
  bool get photoEditingAvailable => _photoSchemaAvailable;
  static const photoPreparationMessage = '複数写真の保存準備中です。保存済みの写真は確認できます。';
  static const _legacyStatusColumns =
      'id, company_id, worker_id, requirement_id, status, expires_at, original_verified, attachment_path, notes, created_at, updated_at';
  static String _statusColumns(bool photos) => photos
      ? _legacyStatusColumns.replaceFirst(
          'attachment_path,',
          'attachment_path, attachment_paths,',
        )
      : _legacyStatusColumns;

  Future<List<Map<String, dynamic>>> _readPhotoStatuses(
    Future<List<Map<String, dynamic>>> Function(bool photos) read,
  ) async {
    try {
      final result = await read(true);
      _photoSchemaAvailable = true;
      return result;
    } on PostgrestException catch (error) {
      if ((error.code != '42703' && error.code != 'PGRST204') ||
          !error.message.contains('attachment_paths')) {
        rethrow;
      }
      // Retry only a proven missing new column. Keep the same RLS filters and
      // propagate permission/network errors instead of hiding them.
      _photoSchemaAvailable = false;
      return read(false);
    }
  }

  static const _requirementColumns =
      'id, company_id, name, scope, upstream_name, company_template_id, is_required, expiry_required, renewal_reminder_days, is_active, sort_order, created_at, updated_at';

  Future<List<Map<String, dynamic>>> _readRequirementRows(
    String companyId, {bool includeHidden = false, bool includeArchived = false,
      String? readToken, void Function()? requireReadScope}
  ) async {
    var archiveSupported = true;
    while (true) {
      requireReadScope?.call();
      try {
        var query = _client.from('document_requirements')
            .select('$_requirementColumns${archiveSupported ? ', archived_at' : ''}')
            .eq('company_id', companyId);
        if (!includeHidden) query = query.eq('is_active', true);
        final ordered = query.order('sort_order').order('name');
        final rows = await (readToken == null ? ordered :
            ordered.setHeader('Authorization', 'Bearer $readToken'));
        requireReadScope?.call();
        return List<Map<String, dynamic>>.from(rows)
            .where((row) => includeArchived || row['archived_at'] == null).toList();
      } on PostgrestException catch (error) {
        requireReadScope?.call();
        if (!archiveSupported ||
            !const ['42703', 'PGRST204'].contains(error.code) ||
            !RegExp(r'(?<![A-Za-z0-9_])archived_at(?![A-Za-z0-9_])')
                .hasMatch(error.message)) {
          rethrow;
        }
        // Old backend remains readable; no archive action is offered without
        // an actual archived_at column in the returned row.
        archiveSupported = false;
      }
    }
  }

  bool _exemptionEditingAvailable = false;
  bool get exemptionEditingAvailable => _exemptionEditingAvailable;

  Future<List<Map<String, dynamic>>> _loadExemptions(String companyId, {
    String? readToken, void Function()? requireReadScope,
  }) async {
    final actor = actorId;
    final token = _client.auth.currentSession?.accessToken;
    try {
      requireReadScope?.call();
      final query = _client.rpc('worker_document_exemption', params: {
        'p_action': 'list', 'p_data': {'company_id': companyId},
      });
      final raw = await (readToken == null ? query :
          query.setHeader('Authorization', 'Bearer $readToken'));
      requireReadScope?.call();
      if (actor == null || actor != actorId ||
          token != _client.auth.currentSession?.accessToken || raw is! Map ||
          raw['capability_version'] != 1 || raw['items'] is! List) {
        throw StateError('書類免除の情報を確認できません。再読み込みしてください。');
      }
      final rows = (raw['items'] as List).map((row) =>
          Map<String, dynamic>.from(row as Map)).toList();
      if (rows.any((row) => row['company_id'] != companyId ||
          row['worker_id'] is! String || row['requirement_id'] is! String ||
          row['active'] is! bool || row['version'] is! int ||
          (row['version'] as int) < 1 || row['reason'] is! String)) {
        throw StateError('書類免除の情報を確認できません。');
      }
      _exemptionEditingAvailable = raw['can_manage'] == true;
      return rows;
    } on PostgrestException catch (error) {
        requireReadScope?.call();
      // Only a confirmed absent candidate endpoint is compatible with the old
      // backend. Authorization/network/data errors must not erase known state.
      if (error.code != 'PGRST202' ||
          !error.message.contains('worker_document_exemption')) { rethrow; }
      _exemptionEditingAvailable = false;
      return [];
    }
  }

  Future<void> setDocumentExemption({required String workerId,
    required String requirementId, required bool active,
    required int expectedVersion, required String reason}) async {
    final actor = actorId;
    final token = _client.auth.currentSession?.accessToken;
    if (!_exemptionEditingAvailable || actor == null || token == null ||
        reason.trim().isEmpty || reason.trim().length > 500 || expectedVersion < 0) {
      throw StateError('書類免除の情報と理由を確認してください。');
    }
    await _requireManagePeople();
    final companyId = await _companyId();
    if (actorId != actor || token != _client.auth.currentSession?.accessToken) {
      throw StateError('ログイン情報が変更されました。');
    }
    final raw = await _client.rpc('worker_document_exemption', params: {
      'p_action': 'set', 'p_data': {'company_id': companyId,
        'worker_id': workerId, 'requirement_id': requirementId, 'active': active,
        'expected_version': expectedVersion, 'reason': reason.trim()},
    });
    if (actorId != actor || token != _client.auth.currentSession?.accessToken ||
        raw is! Map || raw['capability_version'] != 1 || raw['item'] is! Map) {
      throw StateError('免除の保存結果を確認できません。再読み込みしてください。');
    }
    final item = raw['item'] as Map;
    if (item['company_id'] != companyId || item['worker_id'] != workerId ||
        item['requirement_id'] != requirementId || item['active'] != active ||
        item['version'] != expectedVersion + 1) {
      throw StateError('免除の保存結果を確認できません。再読み込みしてください。');
    }
  }

  Future<List<Map<String, dynamic>>> loadArchivedRequirements() async {
    final actor = actorId;
    await _requireManagePeople();
    final companyId = await _companyId();
    final rows = await _readRequirementRows(companyId,
        includeHidden: true, includeArchived: true);
    if (actor == null || actorId != actor) {
      throw StateError('ログイン情報が変更されました。');
    }
    return rows.where((row) => row['archived_at'] != null).toList();
  }

  Future<void> archiveRequirement(Map<String, dynamic> row) =>
      _setRequirementArchived(row, restore: false);

  Future<void> restoreRequirement(Map<String, dynamic> row) =>
      _setRequirementArchived(row, restore: true);

  Future<void> _setRequirementArchived(
    Map<String, dynamic> row, {required bool restore}
  ) async {
    final actor = actorId;
    final token = _client.auth.currentSession?.accessToken;
    const columns = ['name', 'scope', 'upstream_name', 'company_template_id',
      'is_required', 'expiry_required', 'renewal_reminder_days', 'is_active',
      'sort_order', 'created_at', 'updated_at', 'archived_at'];
    final id = row['id'];
    if (actor == null || token == null || id is! String || id.isEmpty ||
        row['company_id'] is! String || row['is_active'] is! bool ||
        !columns.every(row.containsKey) ||
        (restore ? row['archived_at'] is! String : row['archived_at'] != null) ||
        !const ['internal', 'upstream', 'both'].contains(row['scope']) ||
        row['updated_at'] is! String ||
        DateTime.tryParse(row['updated_at'] as String) == null) {
      throw StateError('書類項目を確認できません。再読み込みしてください。');
    }
    await _requireManagePeople();
    final companyId = await _companyId();
    if (actorId != actor ||
        _client.auth.currentSession?.accessToken != token ||
        row['company_id'] != companyId) {
      throw StateError('会社またはログイン情報が変更されました。再読み込みしてください。');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    // Compare every persisted content column, not only updated_at: old writers
    // do not necessarily advance timestamps. Preserve the existing unique key.
    var query = _client.from('document_requirements')
        .update({'archived_at': restore ? null : now,
          'is_active': false, 'updated_at': now})
        .eq('company_id', companyId).eq('id', id);
    for (final column in columns) {
      final value = row[column];
      query = value == null ? query.isFilter(column, null) : query.eq(column, value);
    }
    final rows = await query.select('id, archived_at, is_active');
    if (actorId != actor || _client.auth.currentSession?.accessToken != token) {
      throw StateError('ログイン情報が変更されました。同じ項目を再確認してください。');
    }
    if (rows.length != 1 || rows.single['id'] != id ||
        (restore ? rows.single['archived_at'] != null : rows.single['archived_at'] == null) ||
        rows.single['is_active'] != false) {
      throw StateError('書類項目が更新されています。再読み込みしてください。');
    }
  }

  /// Metadata only, through the existing table/RLS. A missing/invisible row
  /// is deliberately unknown, not proof that another employee has no account.
  Future<List<Map<String, dynamic>>> _bankRegistrationMetadata(
      String companyId, List<Map<String, dynamic>> workers) async {
    if (workers.isEmpty) { return []; }
    final current = await captureAttachmentReadScope();
    final actor = actorId;
    final token = _client.auth.currentSession?.accessToken;
    void check() {
      if (!current() || actor == null || actorId != actor || token == null ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('口座の登録状態を再確認してください。');
      }
    }
    check();
    final ids = workers.map((row) => row['id']?.toString()).whereType<String>().toSet();
    if (ids.length != workers.length || workers.any((row) => row['company_id'] != companyId || row['status'] != 'active')) {
      throw StateError('対象社員を確認できません。');
    }
    try {
      final rows = await _client.from('worker_private_bank_accounts')
          .select('worker_id,company_id,updated_at')
          .eq('company_id', companyId).inFilter('worker_id', ids.toList())
          .setHeader('Authorization', 'Bearer $token')
          .timeout(const Duration(seconds: 30));
      check();
      final values = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      if (values.any((row) => row['company_id'] != companyId ||
          !ids.contains(row['worker_id']) ||
          DateTime.tryParse(row['updated_at']?.toString() ?? '') == null ||
          row.keys.toSet().difference({'worker_id', 'company_id', 'updated_at'}).isNotEmpty) ||
          values.map((row) => row['worker_id']).toSet().length != values.length) {
        throw StateError('口座の登録状態を確認できません。');
      }
      final currentWorkers = await _client.from('workers').select('id,company_id,status')
          .eq('company_id', companyId).eq('status', 'active').inFilter('id', ids.toList())
          .setHeader('Authorization', 'Bearer $token').timeout(const Duration(seconds: 30));
      check();
      if (currentWorkers.length != ids.length || currentWorkers.any((row) =>
          row['company_id'] != companyId || row['status'] != 'active' || !ids.contains(row['id'])) ||
          currentWorkers.map((row) => row['id']).toSet().length != ids.length) {
        throw StateError('対象社員が変更されました。再読み込みしてください。');
      }
      return values;
    } on PostgrestException {
      check();
      // No grant or RLS change is made to obtain missing evidence.
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadAll({bool includeHiddenRequirements = false}) async {
    final session = _client.auth.currentSession;
    final actor = actorId;
    final current = await captureAttachmentReadScope();
    final token = session?.accessToken;
    bool uuid(Object? value) => value is String && RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false).hasMatch(value);
    void check() {
      if (!current() || actor == null || actorId != actor || token == null ||
          !identical(session, _client.auth.currentSession)) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
    }
    check();
    if (!uuid(actor)) throw StateError('本人を確認できません。');
    Future<({String companyId, String role})> readMembership() async {
      check();
      final rows = await _client.from('company_members').select('company_id, role')
          .eq('user_id', actor!).limit(2)
          .setHeader('Authorization', 'Bearer $token');
      check();
      if (rows.length != 1 || !uuid(rows.single['company_id']) ||
          !const ['owner', 'admin', 'manager', 'viewer'].contains(rows.single['role'])) {
        throw StateError('所属会社と権限を確認できません。');
      }
      return (companyId: rows.single['company_id'] as String,
          role: rows.single['role'] as String);
    }
    final initialMembership = await readMembership();
    final companyId = initialMembership.companyId;
    final canManage = initialMembership.role != 'viewer';

    // A history read must not invoke the legacy initializer, which can reactivate
    // an existing inactive worker. Resolve the existing identity without writes.
    Future<List<Map<String, dynamic>>> readOwnWorker() async {
      check();
      final rows = await _client.from('workers')
          .select('id, company_id, user_id, name, affiliation, status')
          .eq('company_id', companyId).eq('user_id', actor!)
          .inFilter('status', ['active', 'inactive']).limit(2)
          .setHeader('Authorization', 'Bearer $token');
      check();
      if (rows.length != 1 || !uuid(rows.single['id']) ||
          rows.single['company_id'] != companyId || rows.single['user_id'] != actor ||
          !const ['active', 'inactive'].contains(rows.single['status'])) {
        throw StateError('本人の保存済み書類を確認できません。');
      }
      return List<Map<String, dynamic>>.from(rows);
    }

    final List<Map<String, dynamic>> workers;
    String? ownWorkerId;
    if (canManage) {
      workers = List<Map<String, dynamic>>.from(await _client.from('workers')
          .select('id, company_id, name, affiliation, status')
          .eq('company_id', companyId).eq('status', 'active').order('name')
          .setHeader('Authorization', 'Bearer $token'));
      check();
    } else {
      workers = await readOwnWorker();
      ownWorkerId = workers.single['id'] as String;
    }
    final exemptions = await _loadExemptions(companyId,
        readToken: token, requireReadScope: check);
    check();
    if (!canManage && exemptions.any((row) => row['worker_id'] != ownWorkerId ||
        !uuid(row['requirement_id']))) {
      throw StateError('本人の書類免除を確認できません。');
    }
    final retainedRequirements = await _readRequirementRows(companyId,
        includeHidden: canManage, includeArchived: canManage,
        readToken: token, requireReadScope: check);
    check();
    if (!canManage && (retainedRequirements.any((row) => !uuid(row['id']) ||
        row['company_id'] != companyId) || retainedRequirements.map((row) => row['id'])
        .toSet().length != retainedRequirements.length)) {
      throw StateError('本人の必要書類項目を確認できません。');
    }
    final requirements = retainedRequirements.where((row) =>
        row['archived_at'] == null &&
        ((includeHiddenRequirements && canManage) || row['is_active'] == true)).toList();
    final statuses = await _readPhotoStatuses((photos) async {
      check();
      var statusesQuery = _client.from('worker_document_statuses')
          .select(_statusColumns(photos)).eq('company_id', companyId);
      if (!canManage) statusesQuery = statusesQuery.eq('worker_id', ownWorkerId!);
      final result = await statusesQuery.setHeader('Authorization', 'Bearer $token');
      check();
      return result;
    });
    if (!canManage && (statuses.any((row) => !uuid(row['id']) ||
        row['company_id'] != companyId || row['worker_id'] != ownWorkerId ||
        !uuid(row['requirement_id'])) ||
        statuses.map((row) => row['id']).toSet().length != statuses.length ||
        statuses.map((row) => row['requirement_id']).toSet().length != statuses.length)) {
      throw StateError('本人の保存済み書類を確認できません。');
    }
    for (final row in statuses) { workerDocumentPaths(row); }
    check();
    // The existing bank metadata reader remains active-only. An inactive own
    // history read has no bank proof; [] must remain unknown, not registered.
    final bankMetadata = requirements.any((row) => row['name'] == '銀行口座情報') &&
        (canManage || workers.single['status'] == 'active')
        ? await _bankRegistrationMetadata(companyId, workers)
        : <Map<String, dynamic>>[];
    check();
    if (!canManage) {
      final verified = await readOwnWorker();
      if (verified.single['id'] != ownWorkerId ||
          verified.single['status'] != workers.single['status']) {
        throw StateError('本人の在籍状態が変更されました。再読み込みしてください。');
      }
      workers.single.remove('user_id');
    }
    final finalMembership = await readMembership();
    check();
    if (finalMembership != initialMembership) {
      throw StateError('所属会社または権限が変更されました。再読み込みしてください。');
    }
    return {
      'bank_account_metadata': bankMetadata,
      'workers': workers,
      'requirements': List<Map<String, dynamic>>.from(requirements),
      'retained_requirements': retainedRequirements,
      'statuses': List<Map<String, dynamic>>.from(statuses),
      'exemptions': exemptions,
    };
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadOwnDocuments() async {
    final worker = await currentWorker();
    final companyId = await _companyId();
    final requirements = await _readRequirementRows(companyId);
    final retainedRequirements = requirements;
    final exemptions = await _loadExemptions(companyId);
    final workers = await _client
        .from('workers')
        .select('id, company_id, name, affiliation, status')
        .eq('company_id', companyId)
        .eq('id', worker.workerId);
    final statuses = await _readPhotoStatuses(
      (photos) async => await _client
          .from('worker_document_statuses')
          .select(_statusColumns(photos))
          .eq('company_id', companyId)
          .eq('worker_id', worker.workerId),
    );
    for (final row in statuses) {
      workerDocumentPaths(row);
    }
    return {
      'workers': List<Map<String, dynamic>>.from(workers),
      'requirements': List<Map<String, dynamic>>.from(requirements),
      'retained_requirements': retainedRequirements,
      'statuses': List<Map<String, dynamic>>.from(statuses),
      'exemptions': exemptions,
    };
  }

  Future<void> addDefaultRequirements({String? scope}) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final existingRows = await _readRequirementRows(companyId,
        includeHidden: true, includeArchived: true);
    final existing = existingRows
        .map((row) => '${row['scope']}::${row['name']}')
        .toSet();

    var order = 0;
    for (final item in defaultRequirements) {
      final name = item['name']! as String;
      if (scope != null && item['scope'] != scope) continue;
      final itemScope = item['scope']! as String;
      final key = '$itemScope::$name';
      if (existing.contains(key)) {
        order += 10;
        continue;
      }
      await _client.from('document_requirements').insert({
        'company_id': companyId,
        'name': name,
        'scope': itemScope,
        'is_required': true,
        'expiry_required': item['expiry']! as bool,
        'renewal_reminder_days': 30,
        'sort_order': order,
      });
      order += 10;
    }
  }

  Future<void> addRequirement({
    required String name,
    required String scope,
    required bool isRequired,
    required bool expiryRequired,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    await _client.from('document_requirements').insert({
      'company_id': companyId,
      'name': name,
      'scope': scope,
      'is_required': isRequired,
      'expiry_required': expiryRequired,
      'renewal_reminder_days': 30,
    });
  }

  Future<void> updateRequirement({
    required String id,
    required String name,
    required String scope,
    required bool isRequired,
    required bool expiryRequired,
  }) => _changeRequirement(id, {
    'name': name.trim(),
    'scope': scope,
    'is_required': isRequired,
    'expiry_required': expiryRequired,
  });

  // Hide the requirement without cascading deletion into submitted documents.
  Future<void> deactivateRequirement(String id) =>
      _changeRequirement(id, {'is_active': false});

  Future<void> setRequirementVisible(String id, bool visible) =>
      _changeRequirement(id, {'is_active': visible}, expectedActive: !visible);

  Future<void> _changeRequirement(
    String id,
    Map<String, dynamic> values, {
    bool expectedActive = true,
  }) async {
    final actor = actorId;
    await _requireManagePeople();
    final companyId = await _companyId();
    if (actor == null || actorId != actor) {
      throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    }
    final rows = await _client
        .from('document_requirements')
        .update(values)
        .eq('company_id', companyId)
        .eq('id', id)
        .eq('is_active', expectedActive)
        .select('id');
    if (actorId != actor) throw StateError('ログイン情報が変更されました。再読み込みしてください。');
    if (rows.length != 1 || rows.single['id'] != id) {
      throw StateError('書類項目を更新できませんでした。再読み込みしてください。');
    }
  }

  /// Verification metadata only; never sends attachment/expiry/notes content.
  Future<void> confirmDocumentStatus(Map<String, dynamic> row, {
    required String status, required bool originalVerified,
  }) async {
    if (!['not_submitted','submitted','verified','missing','expired'].contains(status)) {
      throw const FormatException('Invalid status');
    }
    final actor = actorId;
    final boundary = createChangeRepository();
    try {
    await _requireManagePeople();
    final companyId = await _companyId();
    if (!boundary.isCurrentActor || actor == null || actor != actorId || row['updated_at'] == null) throw StateError('書類を再読み込みしてください。');
    final rows = await _client.from('worker_document_statuses').update({
      'status': status, 'original_verified': originalVerified,
      'updated_at': DateTime.now().toUtc().toIso8601String(), 'updated_by': actor,
    }).eq('company_id',companyId).eq('id',row['id']).eq('worker_id',row['worker_id'])
      .eq('requirement_id',row['requirement_id']).eq('updated_at',row['updated_at']).select('id');
    if (actor != actorId || rows.length != 1 || rows.single['id'] != row['id']) throw StateError('書類を更新できません。再読み込みしてください。');
    } finally { await boundary.dispose(); }
  }

  Future<Map<String, dynamic>> uploadAttachment({
    required String statusId,
    required String workerId,
    required String requirementId,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    await _requireManagePeople();
    final row = await _attachmentRow(statusId, workerId, requirementId);
    return saveAttachmentPhotos(
      row: row,
      photos: [WorkerDocumentPhoto.pending(bytes, originalFilename)],
    );
  }

  Future<String> createSignedAttachmentUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10);
  }

  Future<Map<String, dynamic>> removeAttachment({
    required String statusId,
    required String storagePath,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final row = await _client
        .from('worker_document_statuses')
        .select()
        .eq('company_id', companyId)
        .eq('id', statusId)
        .single();
    return saveAttachmentPhotos(
      row: row,
      photos: [
        for (final path in workerDocumentPaths(row))
          if (path != storagePath) WorkerDocumentPhoto.saved(path),
      ],
    );
  }

  Future<Map<String, dynamic>> _attachmentRow(
    String statusId,
    String workerId,
    String requirementId,
  ) async {
    final companyId = await _companyId();
    return _client
        .from('worker_document_statuses')
        .select()
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('requirement_id', requirementId)
        .eq('id', statusId)
        .single();
  }

  /// Preserve historical and uncertain objects. Removing a photo here only
  /// removes it from the current list; official document history retains it.
  Future<Map<String, dynamic>> saveAttachmentPhotos({
    required Map<String, dynamic> row,
    required List<WorkerDocumentPhoto> photos,
    bool own = false,
  }) async {
    if (!_photoSchemaAvailable) throw StateError(photoPreparationMessage);
    if (own) {
      final worker = await currentWorker();
      if (row['worker_id'] != worker.workerId) {
        throw StateError('本人の書類情報を確認できません。');
      }
    } else {
      await _requireManagePeople();
    }
    final companyId = await _companyId();
    if (row['company_id'] != null && row['company_id'] != companyId) {
      throw StateError('所属会社の書類情報を確認できません。');
    }
    final id = row['id']?.toString() ?? '';
    final workerId = row['worker_id']?.toString() ?? '';
    final requirementId = row['requirement_id']?.toString() ?? '';
    if (id.isEmpty ||
        workerId.isEmpty ||
        requirementId.isEmpty ||
        row['updated_at'] == null) {
      throw StateError('書類情報が不足しています。');
    }
    final paths = await _uploadPhotos(
      photos,
      existing: workerDocumentPaths(row),
      prefix: '$companyId/$workerId/$requirementId/$id',
    );
    var query = _client
        .from('worker_document_statuses')
        .update({
          'attachment_path': paths.isEmpty ? null : paths.first,
          'attachment_paths': paths,
          if (own) 'status': 'submitted',
          if (own) 'original_verified': false,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('requirement_id', requirementId)
        .eq('id', id);
    if (row['updated_at'] != null) {
      query = query.eq('updated_at', row['updated_at']);
    }
    final saved = await query.select().single();
    _confirmPaths(saved, paths);
    return saved;
  }

  Future<List<String>> _uploadPhotos(
    List<WorkerDocumentPhoto> photos, {
    required List<String> existing,
    required String prefix,
    void Function()? requireActor,
  }) async {
    if (photos.length > 20) throw ArgumentError('写真は20枚以内で登録してください。');
    final retained = photos
        .where((photo) => photo.path != null)
        .map((photo) => photo.path!)
        .toList();
    if (retained.toSet().length != retained.length ||
        retained.any((path) => !existing.contains(path))) {
      throw StateError('保存済み写真の情報が変更されています。再読み込みしてください。');
    }
    if (photos.any(
      (photo) =>
          photo.path == null &&
          (photo.bytes == null ||
              photo.bytes!.isEmpty ||
              photo.filename == null ||
              photo.filename!.trim().isEmpty),
    )) {
      throw ArgumentError('写真データとファイル名を確認してください。');
    }
    final paths = <String>[];
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      if (photo.path != null) {
        paths.add(photo.path!);
      } else {
        final path =
            '$prefix/${DateTime.now().microsecondsSinceEpoch}_$index${_extensionOf(photo.filename!)}';
        requireActor?.call();
        await _client.storage
            .from(_bucket)
            .uploadBinary(
              path,
              photo.bytes!,
              fileOptions: _extensionOf(photo.filename!) == '.pdf'
                  ? const FileOptions(upsert: false, contentType: 'application/pdf')
                  : const FileOptions(upsert: false),
            );
        requireActor?.call();
        paths.add(path);
      }
    }
    return paths;
  }

  void _confirmPaths(Map<String, dynamic> row, List<String> expected) {
    final actual = workerDocumentPaths(row);
    if (actual.length != expected.length ||
        List.generate(
          expected.length,
          (i) => i,
        ).any((i) => actual[i] != expected[i])) {
      throw StateError('写真の保存結果が確認できません。再読み込みしてください。');
    }
  }

  Future<void> saveOwnDocumentPhotos({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    required List<WorkerDocumentPhoto> photos,
    required List<String> expectedPaths,
  }) async {
    if (!_photoSchemaAvailable) throw StateError(photoPreparationMessage);
    final worker = await currentWorker();
    final companyId = await _companyId();
    final existing = await _client
        .from('worker_document_statuses')
        .select()
        .eq('company_id', companyId)
        .eq('worker_id', worker.workerId)
        .eq('requirement_id', requirementId)
        .limit(1);
    final row = existing.isEmpty ? null : existing.first;
    if (row != null && row['updated_at'] == null) {
      throw StateError('書類の更新時刻を確認できません。再読み込みしてください。');
    }
    final currentPaths = workerDocumentPaths(row);
    if (currentPaths.length != expectedPaths.length ||
        List.generate(
          expectedPaths.length,
          (i) => i,
        ).any((i) => currentPaths[i] != expectedPaths[i])) {
      throw StateError('登録写真が更新されています。再読み込みしてください。');
    }
    final id = row?['id']?.toString() ?? 'own-upload';
    final paths = await _uploadPhotos(
      photos,
      existing: workerDocumentPaths(row),
      prefix: '$companyId/${worker.workerId}/$requirementId/$id',
    );
    final payload = {
      'company_id': companyId,
      'worker_id': worker.workerId,
      'requirement_id': requirementId,
      'status': 'submitted',
      'attachment_path': paths.isEmpty ? null : paths.first,
      'attachment_paths': paths,
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': false,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final Map<String, dynamic> saved;
    if (row == null) {
      saved = await _client
          .from('worker_document_statuses')
          .insert(payload)
          .select()
          .single();
    } else {
      var query = _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('company_id', companyId)
          .eq('worker_id', worker.workerId)
          .eq('requirement_id', requirementId)
          .eq('id', id);
      if (row['updated_at'] != null) {
        query = query.eq('updated_at', row['updated_at']);
      }
      saved = await query.select().single();
    }
    _confirmPaths(saved, paths);
  }

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    final sanitized = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    return sanitized.isEmpty ? '.jpg' : sanitized;
  }

  Future<({String workerId, String workerName})> currentWorker() async {
    // The existing initializer has no company argument. Admit it only after
    // confirming one membership; never provision an arbitrary first company.
    final session = _client.auth.currentSession;
    final current = await captureAttachmentReadScope();
    final actor = _client.auth.currentUser?.id;
    if (session == null || actor == null || !current() ||
        !identical(session, _client.auth.currentSession)) {
      throw StateError('本人の社員情報を確認できません。');
    }
    final companyId = await _companyId();
    if (!current() || !identical(session, _client.auth.currentSession)) {
      throw StateError('ログイン情報が変更されました。画面を開き直してください。');
    }
    final raw = await _client.rpc('ensure_current_user_worker')
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!current() || !identical(session, _client.auth.currentSession)) {
      throw StateError('ログイン情報が変更されました。画面を開き直してください。');
    }
    final workerId = raw?.toString() ?? '';
    if (workerId.isEmpty) { throw StateError('本人の社員情報を確認できません。'); }
    final row = await _client
        .from('workers')
        .select('name')
        .eq('id', workerId)
        .eq('company_id', companyId)
        .eq('user_id', actor)
        .eq('status', 'active')
        .maybeSingle()
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!current() || !identical(session, _client.auth.currentSession) || row == null) {
      throw StateError('本人と所属会社の社員情報を確認できません。');
    }
    final name = row['name']?.toString().trim();
    return (
      workerId: workerId,
      workerName: name?.isNotEmpty == true ? name! : '本人',
    );
  }

  Future<void> updateOwnStatus({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
  }) async {
    final worker = await currentWorker();
    final companyId = await _companyId();
    final existing = await _client
        .from('worker_document_statuses')
        .select('id')
        .eq('company_id', companyId)
        .eq('worker_id', worker.workerId)
        .eq('requirement_id', requirementId)
        .limit(1);
    final payload = {
      'company_id': companyId,
      'worker_id': worker.workerId,
      'requirement_id': requirementId,
      'status': 'submitted',
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': false,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (existing.isEmpty) {
      await _client
          .from('worker_document_statuses')
          .insert(payload)
          .select('id')
          .single();
    } else {
      await _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('company_id', companyId)
          .eq('worker_id', worker.workerId)
          .eq('requirement_id', requirementId)
          .eq('id', existing.first['id'])
          .select('id')
          .single();
    }
  }

  /// Upload first: rejected/cancelled uploads must not mark a document submitted.
  /// Keep old and uncertain uploads because Storage and status writes are separate.
  Future<void> saveOwnDocument({
    required String requirementId,
    DateTime? expiresAt,
    required String notes,
    Uint8List? attachmentBytes,
    String? originalFilename,
    bool requireEmptyAttachment = false,
  }) async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) throw StateError('SKOへのログインが必要です。');
    void requireActor() {
      if (_client.auth.currentUser?.id != actor) {
        throw StateError('ログインが変更されました。書類一覧を開き直してください。');
      }
    }

    if ((attachmentBytes == null) != (originalFilename == null)) {
      throw ArgumentError('写真データとファイル名を確認してください。');
    }
    if (attachmentBytes == null) {
      await updateOwnStatus(
        requirementId: requirementId,
        expiresAt: expiresAt,
        notes: notes,
      );
      requireActor();
      return;
    }
    final worker = await currentWorker();
    requireActor();
    final companyId = await _companyId();
    requireActor();
    final existing = await _client
        .from('worker_document_statuses')
        .select('id, attachment_path')
        .eq('company_id', companyId)
        .eq('worker_id', worker.workerId)
        .eq('requirement_id', requirementId)
        .limit(1);
    requireActor();
    if (requireEmptyAttachment &&
        existing.isNotEmpty &&
        (existing.first['attachment_path']?.toString() ?? '').isNotEmpty) {
      throw StateError('保存済みの写真は保持します。複数写真の準備後に追加してください。');
    }
    final slot = existing.isEmpty
        ? 'own-upload'
        : existing.first['id'].toString();
    final objectName =
        '${DateTime.now().microsecondsSinceEpoch}${_extensionOf(originalFilename!)}';
    final path =
        '$companyId/${worker.workerId}/$requirementId/$slot/$objectName';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          attachmentBytes,
          fileOptions: path.toLowerCase().endsWith('.pdf')
              ? const FileOptions(upsert: false, contentType: 'application/pdf')
              : const FileOptions(upsert: false),
        );
    requireActor();
    final payload = {
      'company_id': companyId,
      'worker_id': worker.workerId,
      'requirement_id': requirementId,
      'status': 'submitted',
      'attachment_path': path,
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': false,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_by': actor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (existing.isEmpty) {
      await _client
          .from('worker_document_statuses')
          .insert(payload)
          .select('id')
          .single();
    } else {
      var update = _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('company_id', companyId)
          .eq('worker_id', worker.workerId)
          .eq('requirement_id', requirementId)
          .eq('id', existing.first['id']);
      if (requireEmptyAttachment) {
        update = update.isFilter('attachment_path', null);
      }
      await update.select('id').single();
    }
    requireActor();
  }

  Future<Map<String, dynamic>> uploadOwnAttachment({
    required String statusId,
    required String requirementId,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    final worker = await currentWorker();
    final row = await _attachmentRow(statusId, worker.workerId, requirementId);
    return saveAttachmentPhotos(
      row: row,
      own: true,
      photos: [WorkerDocumentPhoto.pending(bytes, originalFilename)],
    );
  }

  /// Register another worker's complete document through existing company ACLs.
  /// Uploads never replace/delete a saved object; one CAS publishes the full list.
  Future<void> saveManagedDocumentPhotos({
    required String workerId,
    required String requirementId,
    required String status,
    DateTime? expiresAt,
    required bool originalVerified,
    required String notes,
    required List<WorkerDocumentPhoto> photos,
    required Map<String, dynamic>? expectedRow,
    void Function()? requireScope,
  }) async {
    if (!_photoSchemaAvailable) throw StateError(photoPreparationMessage);
    final actor = _client.auth.currentUser?.id;
    void requireActor() {
      requireScope?.call();
      if (actor == null || _client.auth.currentUser?.id != actor) {
        throw StateError('ログイン情報が変更されました。再読み込みしてください。');
      }
    }

    requireActor();
    await _requireManagePeople();
    requireActor();
    final companyId = await _companyId();
    requireActor();
    final worker = await _client
        .from('workers')
        .select('id,company_id,status')
        .eq('id', workerId)
        .eq('company_id', companyId)
        .maybeSingle();
    requireActor();
    final requirement = await _client
        .from('document_requirements')
        .select('id,company_id,is_active')
        .eq('id', requirementId)
        .eq('company_id', companyId)
        .eq('is_active', true)
        .maybeSingle();
    requireActor();
    if (worker == null || requirement == null) {
      throw StateError('所属会社の社員と必要書類を確認してください。');
    }
    if (photos.any((photo) => photo.path == null) &&
        worker['status'] != 'active') {
      throw StateError('在籍中の社員の書類へ写真を登録してください。');
    }
    final fresh = await _client
        .from('worker_document_statuses')
        .select()
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('requirement_id', requirementId)
        .maybeSingle();
    requireActor();
    if ((fresh == null) != (expectedRow == null) ||
        (fresh != null &&
            (fresh['id'] != expectedRow!['id'] ||
                fresh['updated_at'] == null ||
                fresh['updated_at'] != expectedRow['updated_at']))) {
      throw StateError('書類が更新されています。再読み込みしてください。');
    }
    final expectedPaths = workerDocumentPaths(expectedRow);
    final currentPaths = workerDocumentPaths(fresh);
    if (expectedPaths.length != currentPaths.length ||
        List.generate(
          expectedPaths.length,
          (i) => i,
        ).any((i) => expectedPaths[i] != currentPaths[i])) {
      throw StateError('登録写真が更新されています。再読み込みしてください。');
    }
    final paths = await _uploadPhotos(
      photos,
      existing: currentPaths,
      prefix:
          '$companyId/$workerId/$requirementId/${fresh?['id'] ?? 'own-upload'}',
      requireActor: requireActor,
    );
    requireActor();
    final payload = <String, dynamic>{
      'company_id': companyId,
      'worker_id': workerId,
      'requirement_id': requirementId,
      'status': status,
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': originalVerified,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'attachment_path': paths.isEmpty ? null : paths.first,
      'attachment_paths': paths,
      'updated_by': actor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final Map<String, dynamic> saved;
    if (fresh == null) {
      saved = await _client
          .from('worker_document_statuses')
          .insert(payload)
          .select()
          .single();
    } else {
      saved = await _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('company_id', companyId)
          .eq('worker_id', workerId)
          .eq('requirement_id', requirementId)
          .eq('id', fresh['id'])
          .eq('updated_at', fresh['updated_at'])
          .select()
          .single();
    }
    requireActor();
    _confirmPaths(saved, paths);
  }

  Future<void> updateStatus({
    required String workerId,
    required String requirementId,
    required String status,
    DateTime? expiresAt,
    required bool originalVerified,
    required String notes,
  }) async {
    final actor = actorId;
    void requireActor() {
      if (actor == null || actorId != actor) {
        throw StateError('ログイン情報が変わりました。画面を開き直してください。');
      }
    }

    requireActor();
    await _requireManagePeople();
    requireActor();
    final companyId = await _companyId();
    requireActor();
    final existing = await _client
        .from('worker_document_statuses')
        .select('id')
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('requirement_id', requirementId)
        .limit(1);
    requireActor();
    final payload = {
      'company_id': companyId,
      'worker_id': workerId,
      'requirement_id': requirementId,
      'status': status,
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': originalVerified,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_by': actor,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    requireActor();
    if (existing.isEmpty) {
      await _client.from('worker_document_statuses').insert(payload);
    } else {
      await _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('company_id', companyId)
          .eq('worker_id', workerId)
          .eq('requirement_id', requirementId)
          .eq('id', existing.first['id']);
    }
    requireActor();
  }
}



