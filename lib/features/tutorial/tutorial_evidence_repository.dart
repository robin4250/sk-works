import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

enum TutorialEvidenceState { unknown, missing, saved, notApplicable }

class TutorialEvidenceCheckpoint {
  const TutorialEvidenceCheckpoint(
    this.key,
    this.state, {
    this.label = '',
    this.evidenceKey,
  });

  final String key;
  final TutorialEvidenceState state;
  final String label;
  final String? evidenceKey;
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

class TutorialEvidenceRepository {
  TutorialEvidenceRepository(this._source, {DateTime? today})
    : _today = today ?? _japanToday();

  final TutorialEvidenceSource _source;
  final DateTime _today;

  static TutorialEvidenceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) { return null; }
    final client = SupabaseBackend.client;
    final user = client.auth.currentUser;
    if (user == null) { return null; }
    return TutorialEvidenceRepository(_SupabaseTutorialEvidenceSource(client, user.id));
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

  /// Caller supplies existing routes visible after role/module/feature checks.
  /// No tutorial completion flags or display-name fallbacks enter this result.
  Future<TutorialEvidenceSnapshot> load({
    required Set<String> availableActionKeys,
  }) async {
    final member = await _read(_source.membership);
    final role = member?['role']?.toString();
    final companyId = member?['company_id']?.toString();
    final tasks = <TutorialEvidenceTask>[];
    if (availableActionKeys.contains('profile')) {
      final profile = await _read(_source.profile);
      tasks.add(TutorialEvidenceTask(
        key: 'personal_profile',
        actionKey: 'profile',
        checkpoints: [
          _field(profile, 'display_name', label: '氏名', evidencePrefix: profile?['user_id']?.toString()),
          _field(profile, 'phone', label: '電話番号', evidencePrefix: profile?['user_id']?.toString()),
        ],
      ));
      final personnel = await _read(_source.personnel);
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
          for (final field in <String, String>{
            'address': '住所', 'blood_type': '血液型', 'role': '職種',
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
      final company = await _read(_source.company);
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
          : await _read(() => _source.documents(companyId));
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
        _source is TutorialSetupEvidenceSource) {
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
          rows = await (_source as TutorialSetupEvidenceSource)
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
    return TutorialEvidenceSnapshot(role: role, tasks: tasks);
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
    const unknown = [TutorialEvidenceCheckpoint('documents', TutorialEvidenceState.unknown, label: '必須書類')];
    if (docs == null || docs['worker_id'] == null ||
        docs['worker_id'].toString().isEmpty ||
        docs['requirements'] is! List || docs['statuses'] is! List) { return unknown; }
    final requirements = (docs['requirements'] as List).whereType<Map>();
    final statuses = (docs['statuses'] as List).whereType<Map>();
    final result = <TutorialEvidenceCheckpoint>[];
    for (final requirement in requirements) {
      if (requirement['is_active'] != true || requirement['is_required'] != true) { continue; }
      final id = requirement['id']?.toString();
      if (id == null || id.isEmpty) { return unknown; }
      final matches = statuses.where((row) =>
        row['requirement_id']?.toString() == id &&
        row['worker_id']?.toString() == docs['worker_id'].toString()).toList();
      var state = TutorialEvidenceState.unknown;
      if (matches.isEmpty) {
        state = TutorialEvidenceState.missing;
      } else if (matches.length == 1) {
        final row = matches.single;
        final status = row['status']?.toString();
        if (['not_submitted', 'missing', 'expired'].contains(status)) {
          state = TutorialEvidenceState.missing;
        } else if (status == 'submitted' || status == 'verified') {
          final rawExpiry = row['expires_at']?.toString() ?? '';
          final expiry = DateTime.tryParse(rawExpiry);
          if (rawExpiry.isNotEmpty && expiry == null) {
            state = TutorialEvidenceState.unknown;
          } else if (requirement['expiry_required'] == true && expiry == null) {
            state = TutorialEvidenceState.missing;
          } else if (expiry != null &&
              DateTime(expiry.year, expiry.month, expiry.day).isBefore(
                DateTime(today.year, today.month, today.day))) {
            state = TutorialEvidenceState.missing;
          } else {
            state = TutorialEvidenceState.saved;
          }
        }
      }
      result.add(TutorialEvidenceCheckpoint('document:$id', state,
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

class _SupabaseTutorialEvidenceSource implements TutorialEvidenceSource, TutorialSetupEvidenceSource {
  _SupabaseTutorialEvidenceSource(this.client, this.userId);

  final SupabaseClient client;
  final String userId;

  @override
  Future<List<Map<String, dynamic>>?> setupRows(String actionKey, String companyId) async {
    if (actionKey == 'trade_companies' || actionKey == 'subcontractors') {
      final raw = await client.rpc('trade_company_workspace');
      if (raw is! List) { return null; }
      final roles = actionKey == 'trade_companies'
          ? {'customer', 'both'} : {'subcontractor', 'both'};
      return [for (final row in raw.whereType<Map>())
        if (roles.contains(row['trade_role']))
          {'id': row['id'], 'name': row['name'], 'configured': true}];
    }
    if (actionKey == 'site_register') {
      final rows = await client.from('sites').select('id,name').eq('company_id', companyId);
      return [for (final row in rows) {...row, 'configured': true}];
    }
    final payroll = actionKey == 'payroll_settings';
    final List<Map<String, dynamic>> targets;
    if (payroll) {
      // Use the same eligible-worker workspace as the existing settings page;
      // never infer payroll eligibility from all company workers.
      final raw = await client.rpc('payroll_workspace');
      if (raw is! Map || raw['permissions'] is! Map ||
          (raw['permissions'] as Map)['edit'] != true || raw['workers'] is! List) {
        return null;
      }
      targets = [for (final row in (raw['workers'] as List).whereType<Map>())
        Map<String, dynamic>.from(row)];
    } else {
      targets = await client.from('partner_companies').select('id,name')
          .eq('company_id', companyId).eq('status', 'active');
    }
    final settings = await client.from(payroll ? 'worker_payroll_settings' : 'partner_payment_settings')
        .select(payroll ? 'worker_id' : 'partner_company_id').eq('company_id', companyId);
    final savedIds = settings.map((row) => row[payroll ? 'worker_id' : 'partner_company_id']?.toString()).toSet();
    // Explicit persisted settings, including legitimate zero rates, count.
    return [for (final row in targets)
      {...row, 'configured': savedIds.contains(row['id']?.toString())}];
  }

  @override
  Future<Map<String, dynamic>?> membership() async => await client
      .from('company_members').select('company_id,role')
      .eq('user_id', userId).maybeSingle();

  @override
  Future<Map<String, dynamic>?> profile() async {
    final row = await client.from('user_profiles').select('user_id,display_name,phone')
        .eq('user_id', userId).maybeSingle();
    return row ?? {'user_id': userId, 'display_name': null, 'phone': null};
  }

  Future<Map<String, dynamic>?> _mapRpc(String name) async {
    final raw = await client.rpc(name);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  @override
  Future<Map<String, dynamic>?> personnel() => _mapRpc('current_worker_personnel_profile');

  @override
  Future<Map<String, dynamic>?> company() => _mapRpc('company_data_state');

  @override
  Future<Map<String, dynamic>?> documents(String companyId) async {
    final worker = await client.from('workers').select('id')
        .eq('user_id', userId).eq('company_id', companyId)
        .eq('status', 'active').maybeSingle();
    if (worker == null) { return null; }
    final workerId = worker['id'];
    final requirements = await client.from('document_requirements')
        .select('id,name,is_active,is_required,expiry_required')
        .eq('company_id', companyId).eq('is_active', true).eq('is_required', true);
    final statuses = await client.from('worker_document_statuses')
        .select('id,requirement_id,worker_id,status,expires_at')
        .eq('company_id', companyId).eq('worker_id', workerId);
    return {'worker_id': workerId, 'requirements': requirements, 'statuses': statuses};
  }
}
