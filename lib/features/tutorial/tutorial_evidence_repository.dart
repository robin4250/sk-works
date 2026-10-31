import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../people/worker_document_exemption.dart';
import '../people/people_cloud_repository.dart';
import '../people/worker_document_photos.dart';
import '../shared/trade_document_form_session.dart';
import '../notifications/required_document_evidence.dart';
import '../notifications/scoped_required_document_attention_repository.dart';

enum TutorialEvidenceState { unknown, missing, saved, notApplicable }

class TutorialEvidenceCheckpoint {
  const TutorialEvidenceCheckpoint(
    this.key,
    this.state, {
    this.label = '',
    this.evidenceKey,
    this.statusLabel,
  });

  final String key;
  final TutorialEvidenceState state;
  final String label;
  final String? evidenceKey;
  /// Presentation only; completion continues to use [state] and saved evidence.
  final String? statusLabel;
}

class TutorialEvidenceTask {
  TutorialEvidenceTask({
    required this.key,
    required this.actionKey,
    required Iterable<TutorialEvidenceCheckpoint> checkpoints,
    this.requiredForCompletion = true,
  }) : checkpoints = List.unmodifiable(checkpoints);

  final String key;
  final String actionKey;
  final bool requiredForCompletion;
  final List<TutorialEvidenceCheckpoint> checkpoints;

  bool get hasUnknown => checkpoints.any(
    (item) => item.state == TutorialEvidenceState.unknown,
  );
}

class TutorialEvidenceSnapshot {
  TutorialEvidenceSnapshot({
    required this.role,
    required Iterable<TutorialEvidenceTask> tasks,
  }) : tasks = List.unmodifiable(tasks);

  /// Null means membership could not be verified, not a general-user role.
  final String? role;
  final List<TutorialEvidenceTask> tasks;
}

/// Injectable read boundary for fixtures. Implementations must never repair,
/// create or update records while measuring saved-data evidence.
abstract interface class TutorialEvidenceSource {
  Future<Map<String, dynamic>?> membership();
  Future<Map<String, dynamic>?> profile();
  Future<Map<String, dynamic>?> personnel();
  Future<Map<String, dynamic>?> company();
  Future<Map<String, dynamic>?> documents(String companyId);
}

/// Optional setup evidence boundary, isolated from personal-data reads.
abstract interface class TutorialSetupEvidenceSource {
  Future<List<Map<String, dynamic>>?> setupRows(String actionKey, String companyId);
}

abstract interface class TutorialOperationalEvidenceSource {
  Future<Map<String, dynamic>?> operationalEvidence(String key, String companyId);
}

class TutorialEvidenceRepository {
  TutorialEvidenceRepository(this._source, {DateTime? today})
    : _today = today ?? _japanToday();

  final TutorialEvidenceSource _source;
  final DateTime _today;

  /// Explicit client boundary for SDK contract verification; no global state.
  factory TutorialEvidenceRepository.forClient(SupabaseClient client, {DateTime? today, String? companyId}) {
    final actor = client.auth.currentUser?.id;
    if (actor == null) { throw StateError('Document evidence requires a session'); }
    return TutorialEvidenceRepository(_SupabaseTutorialEvidenceSource(client, actor, companyId: companyId), today: today);
  }

  static TutorialEvidenceRepository? maybeCreate({String? companyId}) {
    if (!SupabaseBackend.isInitialized) { return null; }
    final client = SupabaseBackend.client;
    final user = client.auth.currentUser;
    if (user == null) { return null; }
    return TutorialEvidenceRepository(_SupabaseTutorialEvidenceSource(client, user.id, companyId: companyId));
  }

  static DateTime _japanToday() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    return DateTime(now.year, now.month, now.day);
  }

  Future<Map<String, dynamic>?> _read(
    Future<Map<String, dynamic>?> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      // Access denial, unavailable schema and network failure are unknown.
      return null;
    }
  }

  TutorialEvidenceCheckpoint _field(
    Map<String, dynamic>? row,
    String key, {
    required String label,
    String? evidencePrefix,
  }) => TutorialEvidenceCheckpoint(
    key,
    row == null || !row.containsKey(key)
        ? TutorialEvidenceState.unknown
        : (row[key]?.toString().trim().isNotEmpty ?? false)
        ? TutorialEvidenceState.saved
        : TutorialEvidenceState.missing,
    label: label,
    evidenceKey: row == null || !row.containsKey(key) || evidencePrefix == null
        ? null : '$evidencePrefix:$key',
  );

  /// Official saved data is independent of writable capability.
  TutorialEvidenceCheckpoint _birthdayField(Map<String, dynamic>? row) {
    const key = 'birth_date';
    const label = '生年月日';
    const unknown = TutorialEvidenceCheckpoint(
      key, TutorialEvidenceState.unknown, label: label,
    );
    final worker = row?['worker_id'];
    final contract = row?['birth_date_contract_version'];
    if (row == null || worker is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(worker) ||
        contract is! int || (contract != 1 && contract != 2) ||
        !row.containsKey(key)) {
      return unknown;
    }
    final digest = row['personnel_cas_digest'];
    if (contract == 2 && (digest is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(digest))) {
      return unknown;
    }
    final value = row[key];
    if (value == null || value == '') {
      return TutorialEvidenceCheckpoint(key, TutorialEvidenceState.missing,
        label: label, statusLabel: '未設定');
    }
    if (value is! String || value != value.trim()) {
      return unknown;
    }
    try {
      PeopleCloudRepository.validatePersonnelMetadata({
        'birthDateSubmitted': true, 'birthDate': value,
      });
    } catch (_) {
      return unknown;
    }
    return TutorialEvidenceCheckpoint(key, TutorialEvidenceState.saved,
      label: label, evidenceKey: '$worker:$key');
  }

  /// Caller supplies existing routes visible after role/module/feature checks.
  /// No tutorial completion flags or display-name fallbacks enter this result.
  Future<TutorialEvidenceSnapshot> load({
    required Set<String> availableActionKeys,
  }) async {
    final original = _source;
    final source = original is _SupabaseTutorialEvidenceSource
        ? await original.capture() : original;
    try {
    final member = await _read(source.membership);
    final role = member?['role']?.toString();
    final companyId = member?['company_id']?.toString();
    final tasks = <TutorialEvidenceTask>[];
    if (availableActionKeys.contains('profile')) {
      final profile = await _read(source.profile);
      tasks.add(TutorialEvidenceTask(
        key: 'personal_profile',
        actionKey: 'profile',
        checkpoints: [
          _field(profile, 'display_name', label: '氏名', evidencePrefix: profile?['user_id']?.toString()),
          _field(profile, 'phone', label: '電話番号', evidencePrefix: profile?['user_id']?.toString()),
        ],
      ));
      final personnel = await _read(source.personnel);
      tasks.add(TutorialEvidenceTask(
        key: 'personnel_profile',
        actionKey: 'profile',
        // The existing personnel editor requires name, not optional medical,
        // address or emergency-contact fields. An absent worker is unknown.
        checkpoints: [_field(personnel, 'name', label: '氏名', evidencePrefix: personnel?['worker_id']?.toString())],
      ));
      tasks.add(TutorialEvidenceTask(
        key: 'personnel_details_recommended',
        actionKey: 'profile',
        requiredForCompletion: false,
        checkpoints: [
          _birthdayField(personnel),
          for (final field in <String, String>{ 'address': '住所', 'blood_type': '血液型', 'role': '職種',
            'emergency_name': '緊急連絡先氏名', 'emergency_relation': '続柄',
            'emergency_phone': '緊急連絡先電話番号', 'emergency_address': '緊急連絡先住所',
          }.entries)
            _field(personnel, field.key, label: field.value,
              evidencePrefix: personnel?['worker_id']?.toString()),
        ],
      ));
    }
    if ((role == 'owner' || role == 'admin') &&
        availableActionKeys.contains('company_documents')) {
      final company = await _read(source.company);
      tasks.add(TutorialEvidenceTask(
        key: 'company_profile',
        actionKey: 'company_documents',
        // Company setup requires its name. Bank, fax and corporate number
        // remain optional and are not included in a completion denominator.
        checkpoints: [_field(company, 'name', label: '会社名', evidencePrefix: companyId)],
      ));
      tasks.add(TutorialEvidenceTask(
        key: 'company_details_recommended',
        actionKey: 'company_documents',
        requiredForCompletion: false,
        checkpoints: [
          for (final field in <String, String>{
            'address': '会社住所', 'phone': '会社電話番号', 'email': '会社メール',
          }.entries)
            _field(company, field.key, label: field.value, evidencePrefix: companyId),
        ],
      ));
    }
    if (availableActionKeys.contains('document_register')) {
      final docs = companyId == null || companyId.isEmpty
          ? null
          : await _read(() => source.documents(companyId));
      tasks.add(TutorialEvidenceTask(
        key: 'required_documents',
        actionKey: 'document_register',
        checkpoints: documentCheckpoints(docs, today: _today),
      ));
    }
    // Registration counts do not prove that a company uses an optional feature.
    // Enabled payroll/payment settings become required for existing targets;
    // an unavailable read must prevent an unsupported completion claim.
    if ((role == 'owner' || role == 'admin' || role == 'manager') &&
        companyId != null && companyId.isNotEmpty &&
        source is TutorialSetupEvidenceSource) {
      for (final entry in <String, String>{
        'trade_companies': '取引会社', 'subcontractors': '下請け会社',
        'site_register': '現場', 'payroll_settings': '個別給与設定',
        'payment_certificate_settings': '支払証明書設定',
      }.entries) {
        if (!availableActionKeys.contains(entry.key)) {
          continue;
        }
        List<Map<String, dynamic>>? rows;
        try {
          rows = await (source as TutorialSetupEvidenceSource)
              .setupRows(entry.key, companyId);
        } catch (_) {
          // RLS rejection and unavailable data must not become missing data.
        }
        tasks.add(TutorialEvidenceTask(
          key: 'setup_${entry.key}', actionKey: entry.key,
          requiredForCompletion:
              (entry.key == 'payroll_settings' ||
                  entry.key == 'payment_certificate_settings') &&
              (rows == null || rows.isNotEmpty),
          checkpoints: setupCheckpoints(entry.key, rows, label: entry.value),
        ));
      }
    }
    if (companyId != null && companyId.isNotEmpty &&
        source is TutorialOperationalEvidenceSource) {
      final actions = <String, String>{
        if ((role == 'owner' || role == 'admin') &&
            availableActionKeys.contains('payroll_settings'))
          'company_payroll_policy': 'company_documents',
        if (role == 'owner' || role == 'admin' || role == 'manager')
          'company_document_selection': 'documents',
        'personal_qualifications': 'qualification_register',
      };
      for (final entry in actions.entries) {
        if (!availableActionKeys.contains(entry.value)) {
          continue;
        }
        Map<String, dynamic>? evidence;
        try {
          evidence = await (source as TutorialOperationalEvidenceSource)
              .operationalEvidence(entry.key, companyId);
        } catch (_) {
          // Missing grants or network data are unknown, never saved evidence.
        }
        tasks.add(TutorialEvidenceTask(
          key: entry.key, actionKey: entry.value,
          requiredForCompletion: entry.key == 'company_payroll_policy',
          checkpoints: operationalCheckpoints(entry.key, evidence, companyId),
        ));
      }
    }
    if (source is _SupabaseTutorialEvidenceSource) { await source.finish(); }
    return TutorialEvidenceSnapshot(role: role, tasks: tasks);
    } finally { if (source is _SupabaseTutorialEvidenceSource) { source.close(); } }
  }

  static List<TutorialEvidenceCheckpoint> operationalCheckpoints(
    String key, Map<String, dynamic>? evidence, String companyId,
  ) {
    TutorialEvidenceCheckpoint checkpoint(String field, String label, bool? valid,
        {String? rowId}) => TutorialEvidenceCheckpoint(field,
          valid == null ? TutorialEvidenceState.unknown
              : valid ? TutorialEvidenceState.saved : TutorialEvidenceState.missing,
          label: label, statusLabel: key == 'company_document_selection' && valid == true
              ? '設定済み' : null, evidenceKey: valid == true
              ? '$key:${rowId ?? companyId}:$field' : null);
    if (key == 'company_payroll_policy') {
      bool? number(String field, int min, int max) {
        if (evidence == null) {
          return null;
        }
        final value = evidence[field];
        return value is int && value >= min && value <= max;
      }
      final reviewers = evidence?['reviewers'];
      bool? validReviewers;
      if (reviewers is List) {
        final selected = reviewers.whereType<Map>()
            .where((row) => row['selected_position'] != null).toList();
        final ids = selected.map((row) => row['user_id']?.toString()).toSet();
        validReviewers = selected.isNotEmpty && selected.length <= 3 &&
            ids.length == selected.length && !ids.contains(null) && !ids.contains('');
      }
      final timingValid = evidence == null ? null
          : number('payment_month_offset', 0, 2) == true &&
              number('payment_day', 1, 31) == true &&
              (evidence['payment_month_offset'] != 0 || evidence['payment_day'] == 31);
      return [
        checkpoint('payment_timing', '給与の支払日整合性', timingValid),
        checkpoint('closing_day', '給与の締め日', number('closing_day', 31, 31)),
        checkpoint('payment_day', '給料日', number('payment_day', 1, 31)),
        checkpoint('payment_month_offset', '給与の支払月', number('payment_month_offset', 0, 2)),
        checkpoint('reviewers', '給与確認者（1〜3名）', validReviewers),
      ];
    }
    final rows = evidence?['rows'];
    if (rows is! List || rows.isEmpty) {
      // There is no stored "no required documents" decision in the current schema.
      return [checkpoint('registration', key == 'company_document_selection'
          ? '必要書類の指定（指定なしの保存証跡は未対応）' : '本人の資格登録',
          key == 'company_document_selection' || rows is! List ? null : false)];
    }
    return [for (final row in rows.whereType<Map>())
      checkpoint('record:${row['id']}', key == 'company_document_selection'
          ? _companyDocumentLabel(row) : row['name']?.toString() ?? '本人の資格',
          row['id']?.toString().isNotEmpty == true ? true : null,
          rowId: row['id']?.toString()),
    ];
  }

  static String _companyDocumentLabel(Map row) {
    final name = row['name']?.toString().trim();
    final scope = switch (row['scope']) {
      'internal' => '社内',
      'upstream' => '取引会社',
      'both' => '社内・取引会社',
      _ => null,
    };
    final label = name == null || name.isEmpty ? '必要書類' : name;
    return scope == null ? label : '$scope：$label';
  }

  static List<TutorialEvidenceCheckpoint> setupCheckpoints(
    String actionKey, List<Map<String, dynamic>>? rows, {required String label}
  ) {
    if (rows == null) {
      return [TutorialEvidenceCheckpoint(
        '$actionKey:registration', TutorialEvidenceState.unknown, label: label)];
    }
    // No partners/payroll workers means no dependent settings to configure.
    if (rows.isEmpty) {
      return [TutorialEvidenceCheckpoint(
      '$actionKey:registration',
      actionKey == 'payroll_settings' || actionKey == 'payment_certificate_settings'
          ? TutorialEvidenceState.notApplicable : TutorialEvidenceState.missing,
      label: label)];
    }
    return [for (final row in rows) TutorialEvidenceCheckpoint(
      '$actionKey:${row['id']}',
      row['id'] == null ? TutorialEvidenceState.unknown
          : row['configured'] == false ? TutorialEvidenceState.missing
          : row['configured'] == null ? TutorialEvidenceState.unknown
          : TutorialEvidenceState.saved,
      label: row['name']?.toString() ?? label,
      evidenceKey: row['configured'] == true ? '$actionKey:${row['id']}' : null,
    )];
  }

  static List<TutorialEvidenceCheckpoint> documentCheckpoints(
    Map<String, dynamic>? docs, {
    required DateTime today,
  }) {
    final canonical = docs?['canonical_evidence'];
    if (canonical is Map) {
      final evidence = RequiredDocumentEvidenceSnapshot.fromJson(canonical);
      if (evidence.items.isEmpty) {
        return const [TutorialEvidenceCheckpoint('documents', TutorialEvidenceState.notApplicable, label: '必須書類')];
      }
      return [for (final item in evidence.items) TutorialEvidenceCheckpoint(
        'document:${item.id}', switch (item.state) {
          RequiredDocumentEvidenceState.saved => TutorialEvidenceState.saved,
          RequiredDocumentEvidenceState.missing => TutorialEvidenceState.missing,
          RequiredDocumentEvidenceState.unknown => TutorialEvidenceState.unknown,
          RequiredDocumentEvidenceState.exempt => TutorialEvidenceState.notApplicable,
        },
        label: item.state == RequiredDocumentEvidenceState.exempt
            ? '${evidence.labelFor(item)}（提出免除）' : evidence.labelFor(item),
        evidenceKey: item.evidenceKey, statusLabel: item.statusLabel.isEmpty ? null : item.statusLabel,
      )];
    }
    const unknown = [TutorialEvidenceCheckpoint('documents', TutorialEvidenceState.unknown, label: '必須書類')];
    if (docs == null || docs['worker_id'] == null ||
        docs['worker_id'].toString().isEmpty ||
        docs['requirements'] is! List || docs['statuses'] is! List) { return unknown; }
    final requirements = (docs['requirements'] as List).whereType<Map>();
    final statuses = (docs['statuses'] as List).whereType<Map>();
    final exemptions = docs['exemptions'] is List
        ? (docs['exemptions'] as List).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : const <Map<String, dynamic>>[];
    final result = <TutorialEvidenceCheckpoint>[];
    for (final requirement in requirements) {
      if (requirement['is_active'] != true || requirement['is_required'] != true) { continue; }
      final id = requirement['id']?.toString();
      if (id == null || id.isEmpty) { return unknown; }
      final exemption = documentExemptionFor(exemptions, docs['worker_id'].toString(), id);
      if (exemption?['active'] == true) {
        result.add(TutorialEvidenceCheckpoint('document:$id', TutorialEvidenceState.notApplicable,
          label: '${requirement['name'] ?? '必須書類'}（提出免除）',
          statusLabel: '免除',
          evidenceKey: 'exemption:$id:${exemption!['version']}'));
        continue;
      }
      if (requirement['name'] == '銀行口座情報') {
        final metadata = docs['bank_account_metadata'];
        final known = docs['bank_account_known'] == true;
        final matching = metadata is Map &&
            metadata['worker_id'] == docs['worker_id'] &&
            docs['company_id'] is String &&
            (docs['company_id'] as String).isNotEmpty &&
            metadata['company_id'] == docs['company_id'] &&
            DateTime.tryParse(metadata['updated_at']?.toString() ?? '') != null;
        result.add(TutorialEvidenceCheckpoint('document:$id',
          !known ? TutorialEvidenceState.unknown
              : metadata == null ? TutorialEvidenceState.missing
              : matching ? TutorialEvidenceState.saved : TutorialEvidenceState.unknown,
          label: '銀行口座情報',
          evidenceKey: known && matching ? 'bank:${docs['worker_id']}:${metadata['updated_at']}' : null,
        ));
        continue;
      }
      final matches = statuses.where((row) =>
        row['requirement_id']?.toString() == id &&
        row['worker_id']?.toString() == docs['worker_id'].toString()).toList();
      var state = TutorialEvidenceState.unknown;
      String? statusLabel;
      if (matches.isEmpty) {
        state = TutorialEvidenceState.missing;
      } else if (matches.length == 1) {
        final row = matches.single;
        final status = row['status']?.toString();
        if (['not_submitted', 'missing'].contains(status)) {
          state = TutorialEvidenceState.missing;
        } else if (status == 'expired') {
          state = TutorialEvidenceState.missing;
          statusLabel = '期限切れ';
        } else if (status == 'submitted' || status == 'verified') {
          final name = requirement['name']?.toString();
          if (name == null || name.isEmpty || name == '銀行口座情報' ||
              (!row.containsKey('attachment_path') && !row.containsKey('attachment_paths'))) {
            // Bank evidence is held separately, and cannot be inferred from status.
            state = TutorialEvidenceState.unknown;
          } else {
            List<String>? paths;
            try { paths = workerDocumentPaths(Map<String, dynamic>.from(row)); } catch (_) {
              statusLabel = '添付情報を確認';
            }
            if (paths == null) {
              state = TutorialEvidenceState.unknown;
            } else if (paths.isEmpty) {
              state = TutorialEvidenceState.missing;
              statusLabel = '添付待ち';
            } else {
            final rawExpiry = row['expires_at']?.toString() ?? '';
            final expiry = DateTime.tryParse(rawExpiry);
            final canonicalExpiry = expiry != null && expiry.year >= 1 &&
                RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawExpiry) &&
                '${expiry.year.toString().padLeft(4, '0')}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}' == rawExpiry;
            if (rawExpiry.isNotEmpty && !canonicalExpiry) {
              state = TutorialEvidenceState.unknown;
              statusLabel = '登録済み・期限を確認';
            } else if (requirement['expiry_required'] == true && expiry == null) {
              state = TutorialEvidenceState.missing;
              statusLabel = '登録済み・期限未入力';
            } else if (expiry != null &&
                DateTime(expiry.year, expiry.month, expiry.day).isBefore(
                  DateTime(today.year, today.month, today.day))) {
              state = TutorialEvidenceState.missing;
              statusLabel = '登録済み・期限切れ';
            } else {
              state = TutorialEvidenceState.saved;
              statusLabel = '提出済み';
            }
            }
          }
        }
      }
      result.add(TutorialEvidenceCheckpoint('document:$id', state,
        statusLabel: statusLabel,
        label: requirement['name']?.toString() ?? '必須書類',
        evidenceKey: matches.length == 1 && matches.single['id'] != null
            ? "${matches.single['id']}:status" : null,
      ));
    }
    return result.isEmpty
        ? const [TutorialEvidenceCheckpoint('documents', TutorialEvidenceState.notApplicable, label: '必須書類')]
        : List.unmodifiable(result);
  }
}

class _SupabaseTutorialEvidenceSource implements TutorialEvidenceSource, TutorialSetupEvidenceSource, TutorialOperationalEvidenceSource {
  _SupabaseTutorialEvidenceSource(this.client, this.userId, {this.companyId});

  final SupabaseClient client;
  final String userId;
  final String? companyId;
  TradeDocumentFormSession? _lease;
  String? _capturedToken;
  List<Map<String,dynamic>> _members = const [];
  bool _legacyCompanyRpcAllowed = false;

  Future<_SupabaseTutorialEvidenceSource> capture() async {
    if (client.auth.currentUser?.id != userId) { throw StateError('ログイン状態が変わりました。'); }
    final scoped = _SupabaseTutorialEvidenceSource(client, userId, companyId: companyId);
    scoped._capturedToken = client.auth.currentSession?.accessToken;
    scoped._lease = TradeDocumentFormSession(client);
    try {
      await scoped._lease!.ready();
      final raw = await scoped._lease!.readOwnMemberships();
      if (raw is! List || raw.any((row) => row is! Map)) { throw StateError('会社を確認できません。'); }
      scoped._members = raw.map((row) => Map<String,dynamic>.from(row as Map)).toList();
      scoped._legacyCompanyRpcAllowed = scoped._members.length == 1 &&
          (companyId == null || scoped._members.single['company_id'] == companyId);
      return scoped;
    } catch (_) { scoped.close(); rethrow; }
  }
  Future<void> finish() async { await _lease!.ready(); }
  void close() { _lease?.dispose(); }
  Future<Object?> _rpc(String name) async {
    if (!_legacyCompanyRpcAllowed) { return null; }
    return _lease!.rpc(name, const {});
  }


  @override
  Future<Map<String, dynamic>?> operationalEvidence(String key, String companyId) async {
    if (key == 'company_payroll_policy') {
      final policy = await _rpc('payroll_company_policy');
      if (policy is! Map || policy['can_manage_settings'] != true) {
        return null;
      }
      final reviewers = await _rpc('payroll_confirmation_candidates');
      return {...Map<String, dynamic>.from(policy), 'reviewers': reviewers};
    }
    if (key == 'company_document_selection') {
      final permissions = await _rpc('current_feature_permissions');
      if (permissions is! Map || permissions['can_manage_people'] != true) {
        return null;
      }
      _lease!.requireScope();
      final rows = await client.from('document_requirements')
          .select('id,name,scope,is_required').eq('company_id', companyId).eq('is_active', true).setHeader('Authorization', 'Bearer $_capturedToken');
      return {'rows': rows};
    }
    _lease!.requireScope();
    final worker = await client.from('workers').select('id')
        .eq('company_id', companyId).eq('user_id', userId).eq('status', 'active').maybeSingle().setHeader('Authorization', 'Bearer $_capturedToken');
    if (worker == null) {
      return null;
    }
    _lease!.requireScope();
    final rows = await client.from('worker_qualifications').select('id')
        .eq('company_id', companyId).eq('worker_id', worker['id']).setHeader('Authorization', 'Bearer $_capturedToken');
    return {'rows': rows};
  }

  @override
  Future<List<Map<String, dynamic>>?> setupRows(String actionKey, String companyId) async {
    if (actionKey == 'trade_companies' || actionKey == 'subcontractors') {
      final raw = await _rpc('trade_company_workspace');
      if (raw is! List) { return null; }
      final roles = actionKey == 'trade_companies'
          ? {'customer', 'both'} : {'subcontractor', 'both'};
      return [for (final row in raw.whereType<Map>())
        if (roles.contains(row['trade_role']))
          {'id': row['id'], 'name': row['name'], 'configured': true}];
    }
    if (actionKey == 'site_register') {
      _lease!.requireScope();
      final rows = await client.from('sites').select('id,name').eq('company_id', companyId).setHeader('Authorization', 'Bearer $_capturedToken');
      return [for (final row in rows) {...row, 'configured': true}];
    }
    final payroll = actionKey == 'payroll_settings';
    final List<Map<String, dynamic>> targets;
    if (payroll) {
      // Use the same eligible-worker workspace as the existing settings page;
      // never infer payroll eligibility from all company workers.
      final raw = await _rpc('payroll_workspace');
      if (raw is! Map || raw['permissions'] is! Map ||
          (raw['permissions'] as Map)['edit'] != true || raw['workers'] is! List) {
        return null;
      }
      targets = [for (final row in (raw['workers'] as List).whereType<Map>())
        Map<String, dynamic>.from(row)];
    } else {
      _lease!.requireScope();
      targets = await client.from('partner_companies').select('id,name')
          .eq('company_id', companyId).eq('status', 'active').setHeader('Authorization', 'Bearer $_capturedToken');
    }
    _lease!.requireScope();
    final settings = await client.from(payroll ? 'worker_payroll_settings' : 'partner_payment_settings')
        .select(payroll ? 'worker_id' : 'partner_company_id').eq('company_id', companyId).setHeader('Authorization', 'Bearer $_capturedToken');
    final savedIds = settings.map((row) => row[payroll ? 'worker_id' : 'partner_company_id']?.toString()).toSet();
    // Explicit persisted settings, including legitimate zero rates, count.
    return [for (final row in targets)
      {...row, 'configured': savedIds.contains(row['id']?.toString())}];
  }

  @override
  Future<Map<String, dynamic>?> membership() async {
    _lease!.requireScope();
    final selected = _members.where((row) => companyId == null || row['company_id'] == companyId).toList();
    return selected.length == 1 && (companyId != null || _members.length == 1) ? selected.single : null;
  }

  @override
  Future<Map<String, dynamic>?> profile() async {
    _lease!.requireScope();
    final row = await client.from('user_profiles').select('user_id,display_name,phone')
        .eq('user_id', userId).maybeSingle().setHeader('Authorization', 'Bearer $_capturedToken');
    return row ?? {'user_id': userId, 'display_name': null, 'phone': null};
  }

  Future<Map<String, dynamic>?> _mapRpc(String name) async {
    final raw = await _rpc(name);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  @override
  Future<Map<String, dynamic>?> personnel() async {
    final member = await membership();
    final selectedCompany = member?['company_id'];
    if (!_legacyCompanyRpcAllowed || selectedCompany is! String) { return null; }
    _lease!.requireScope();
    final workers = await client.from('workers').select('id')
        .eq('company_id', selectedCompany).eq('user_id', userId).eq('status', 'active')
        .limit(2).setHeader('Authorization', 'Bearer $_capturedToken');
    if (workers.length != 1) { return null; }
    final row = await _mapRpc('current_worker_personnel_profile');
    return row?['worker_id'] == workers.single['id'] ? row : null;
  }

  @override
  Future<Map<String, dynamic>?> company() => _mapRpc('company_data_state');

  @override
  Future<Map<String, dynamic>?> documents(String companyId) async {
    _lease!.requireScope();
    final receipt = await ScopedRequiredDocumentAttentionRepository(client).load(companyId: companyId);
    _lease!.requireScope();
    return {'canonical_evidence': receipt};
  }
}
