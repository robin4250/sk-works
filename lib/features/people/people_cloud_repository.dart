import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PersonnelScopeChanged implements Exception {
  const PersonnelScopeChanged();
  @override String toString() => '会社またはログイン情報が変更されました。開き直してください。';
}

class PersonnelPrivacySnapshot {
  const PersonnelPrivacySnapshot({required this.actor, required this.company,
    required this.role, required this.canManage, required this.records});
  final String actor, company, role;
  final bool canManage;
  final List<Map<String,dynamic>> records;
}

/// Page-local data lease. No passwords, roles or memberships are persisted.
/// Remote changes are detected by foreground polling (15s) and fresh actions,
/// not instant revocation. No Realtime publication/configuration is changed.
class PersonnelPrivacySession extends ChangeNotifier with WidgetsBindingObserver {
  PersonnelPrivacySession({required this.actor, required this.company,
    required this.currentActor, required this.load, this.actorChanges,
    this.interval = const Duration(seconds:15)});
  final String? actor;
  final String company;
  final String? Function() currentActor;
  final Future<PersonnelPrivacySnapshot> Function() load;
  final Stream<String?>? actorChanges;
  final Duration interval;
  StreamSubscription<String?>? _subscription;
  Timer? _timer;
  PersonnelPrivacySnapshot? snapshot;
  Object? error;
  int _epoch=0, _request=0;
  bool _active=true, _revoked=false, _disposed=false, _started=false;
  int get epoch=>_epoch;
  bool get revoked=>_revoked;
  bool get active=>_active;
  void start() {
    if(_started)return; _started=true;
    WidgetsBinding.instance.addObserver(this);
    _subscription=actorChanges?.listen((value){if(value!=actor)revoke();},onError:(_)=>revoke());
    _startTimer(); unawaited(refresh());
  }
  void _startTimer(){_timer?.cancel();_timer=Timer.periodic(interval,(_){if(_active)unawaited(refresh());});}
  void _clear(Object reason,{bool permanent=false}) {
    if(_disposed)return;
    _request++;_epoch++;snapshot=null;error=reason;_revoked=_revoked||permanent;
    notifyListeners();
  }
  void revoke()=>_clear(const PersonnelScopeChanged(),permanent:true);
  void verify(int lease) {
    if(_disposed||!_active||_revoked||actor==null||currentActor()!=actor||lease!=_epoch||snapshot==null)throw const PersonnelScopeChanged();
  }
  Future<void> refresh() async {try{await read();}catch(_){/* State was cleared; no stale fallback. */}}
  Future<List<Map<String,dynamic>>> read({Set<String>? workerIds,bool forExport=false}) async {
    if(_disposed||!_active||_revoked||actor==null||currentActor()!=actor){revoke();throw const PersonnelScopeChanged();}
    final request=++_request, lease=_epoch;
    PersonnelPrivacySnapshot value;
    try { value=await load().timeout(const Duration(seconds:10)); }
    catch(e){if(request==_request)_clear(e,permanent:e is PersonnelScopeChanged);rethrow;}
    if(_disposed||!_active||_revoked||request!=_request||lease!=_epoch||currentActor()!=actor||value.actor!=actor||value.company!=company){
      if(!_disposed&&request==_request)revoke();throw const PersonnelScopeChanged();
    }
    final previous=snapshot;
    if(previous!=null&&(previous.role!=value.role||previous.canManage!=value.canManage))_epoch++;
    snapshot=value;error=null;notifyListeners();
    if(forExport&&!value.canManage)throw StateError('社員情報を出力する権限がありません');
    final rows=workerIds==null?value.records:value.records.where((row)=>workerIds.contains(row['id']?.toString())).toList(growable:false);
    if(workerIds!=null&&rows.length!=workerIds.length)throw StateError('対象の社員情報を再確認してください');
    return rows;
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused||state==AppLifecycleState.hidden){_active=false;_timer?.cancel();_clear(StateError('本人確認を再確認しています'));}
    if(state==AppLifecycleState.resumed&&!_revoked&&!_disposed){_active=true;_startTimer();unawaited(refresh());}
  }
  @override void dispose(){
    if(_disposed)return;_disposed=true;_epoch++;_request++;snapshot=null;_timer?.cancel();_subscription?.cancel();
    if(_started)WidgetsBinding.instance.removeObserver(this);super.dispose();
  }
}

class PersonnelPrivacyView extends StatefulWidget {
  const PersonnelPrivacyView({super.key,required this.session,required this.builder});
  final PersonnelPrivacySession session;
  final Widget Function(BuildContext,List<Map<String,dynamic>>) builder;
  @override State<PersonnelPrivacyView> createState()=>_PersonnelPrivacyViewState();
}
class _PersonnelPrivacyViewState extends State<PersonnelPrivacyView> {
  @override void initState(){super.initState();widget.session.addListener(_changed);unawaited(widget.session.refresh());}
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){widget.session.removeListener(_changed);super.dispose();}
  @override Widget build(BuildContext context){
    final s=widget.session, value=s.snapshot;
    if(value!=null&&!s.revoked&&s.active)return widget.builder(context,value.records);
    return Directionality(textDirection:TextDirection.ltr,child:Center(child:Text(s.error==null?'社員情報を確認しています…':'社員情報を表示できません。画面を閉じて再確認してください。')));
  }
}

class PeopleCloudRepository {
  PeopleCloudRepository._(this._client) : _actorForTesting=null;
  @visibleForTesting PeopleCloudRepository.forTesting(this._client,{String? Function()? actor}) : _actorForTesting=actor;
  final String? Function()? _actorForTesting;

  final SupabaseClient _client;

  static PeopleCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PeopleCloudRepository._(client);
  }

  Future<({String companyId, String role})> membership({String? companyId}) async {
    final userId = actorId;
    if (userId == null) throw StateError('SKOへのログインが必要です。');
    var query = _client.from('company_members').select('company_id, role').eq('user_id', userId);
    if(companyId!=null)query=query.eq('company_id',companyId);
    final rows=await query.limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return (
      companyId: rows.first['company_id'] as String,
      role: rows.first['role']?.toString() ?? 'viewer',
    );
  }

  Future<String> companyName({String? companyId}) async {
    final member = await membership(companyId:companyId);
    final row = await _client
        .from('companies')
        .select('name')
        .eq('id', member.companyId)
        .maybeSingle();
    return row?['name']?.toString() ?? '';
  }

  Future<bool> canManagePeople({String? companyId}) async {
    try { return (await readPersonnel(expectedCompany:companyId)).canManage; }
    on PostgrestException catch(error){if(error.code=='42501')return false;rethrow;}
  }

  Future<bool> canConfigurePersonnelApprovers({String? companyId}) async {
    final member = await membership(companyId:companyId);
    return member.role == 'owner' || member.role == 'admin';
  }

  Future<void> _requireManagePeople() async {
    if (!await canManagePeople()) {
      throw StateError('社員情報は管理者・サブ管理者のみ利用できます。');
    }
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('SKOへのログインが必要です。');
    }
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) {
      throw StateError('会社情報が見つかりません。');
    }
    return rows.first['company_id'] as String;
  }

  String? get actorId => _actorForTesting?.call() ?? _client.auth.currentUser?.id;

  Future<bool> canViewPeople({String? companyId}) async {
    try { await readPersonnel(expectedCompany:companyId); return true; }
    on PostgrestException catch (error) { if (error.code == '42501') return false; rethrow; }
  }

  Future<PersonnelPrivacySnapshot> readPersonnel({String? expectedCompany}) async {
    final actor = actorId;
    final member = await membership(companyId:expectedCompany);
    if (expectedCompany != null && member.companyId != expectedCompany) {
      throw const PersonnelScopeChanged();
    }
    final raw = await _client.rpc('employee_personnel_view', params: {'p_company': member.companyId});
    // Successful canonical read proves the scoped manager feature; viewer remains read-only.
    final manage = ['owner','admin','manager'].contains(member.role);
    final after = await membership(companyId:member.companyId);
    if (actor == null || actorId != actor || after != member) {
      throw const PersonnelScopeChanged();
    }
    if (raw is! Map || raw['company_id'] != member.companyId || raw['records'] is! List) {
      throw StateError('社員情報の取得結果を確認できません');
    }
    return PersonnelPrivacySnapshot(actor: actor, company: member.companyId,
      role: member.role, canManage: manage,
      records: (raw['records'] as List).whereType<Map>().where((row)=>row['active']==true)
        .map((row) => Map<String,dynamic>.from(row)).toList(growable: false));
  }

  PersonnelPrivacySession privacySession(String company) => PersonnelPrivacySession(
    actor: actorId, company: company, currentActor: () => actorId,
    load: () => readPersonnel(expectedCompany: company),
    actorChanges: _client.auth.onAuthStateChange.map((event) => event.session?.user.id),
  );

  Future<String?> portraitUrl(String workerId,{String? companyId}) async {
    final actor = actorId;
    final member = await membership(companyId:companyId);
    final path = await _client.rpc(
      'employee_personnel_portrait',
      params: {'p_company': member.companyId, 'p_worker': workerId},
    );
    if (actor == null || actorId != actor) throw StateError('ログイン情報が変更されました');
    if (path == null) return null;
    final value = path.toString();
    if (!value.startsWith('${member.companyId}/$workerId/')) {
      throw StateError('顔写真の所属が一致しません');
    }
    final url = await _client.storage
        .from('worker-documents')
        .createSignedUrl(value, 600);
    if (actorId != actor) throw StateError('ログイン情報が変更されました');
    return url;
  }

  Future<List<Map<String, dynamic>>> loadAll({String? expectedCompany}) async {
    final member = await membership(companyId:expectedCompany);
    if (member.role == 'viewer') return (await readPersonnel(expectedCompany:member.companyId)).records;
    if (!['owner','admin','manager'].contains(member.role)) throw StateError('社員一覧の閲覧権限がありません');
    Future<List<Map<String,dynamic>>> basicRows() async {
      // Contact columns are intentionally not directly granted. Preserve the
      // RLS-authorized basic roster without selecting phone/email/private data.
      final partners=await _client.from('partner_companies').select('id,name,trade_role,status').eq('company_id',member.companyId);
      final byId={for(final row in partners)row['id'].toString():row['name']?.toString()??''};
      final workers=await _client.from('workers').select('id,name,role,affiliation,status,partner_company_id').eq('company_id',member.companyId);
      return [
        for(final row in partners)<String,dynamic>{...row,'kind':'partnerCompany','role':row['trade_role'],'active':row['status']=='active'},
        for(final row in workers)<String,dynamic>{...row,'kind':row['affiliation']=='partner_company'?'partnerWorker':'employee',
          'company_name':byId[row['partner_company_id']?.toString()]??'','active':row['status']=='active'},
      ];
    }
    dynamic rows;
    final memberships=await _client.from('company_members').select('company_id').eq('user_id',actorId!).limit(2);
    if(memberships.length==1&&memberships.single['company_id']==member.companyId){
      try { rows = await _client.rpc('people_management_records'); }
      on PostgrestException catch (error) {
        if(error.code!='42501'&&!(error.code=='P0001'&&error.message=='people management permission required'))rethrow;
        rows=await basicRows();
      }
    } else {
      // The old no-argument RPC chooses an arbitrary first company; never use it
      // to populate an explicitly different company in a multi-company account.
      rows=await basicRows();
    }
    if (rows is! List) return const <Map<String, dynamic>>[];

    var personnelRows = <Map<String,dynamic>>[];
    try { personnelRows = (await readPersonnel(expectedCompany: member.companyId)).records; }
    on PostgrestException catch (error) { if (error.code != '42501') rethrow; }
    final personnelByWorker = <String, Map<String, dynamic>>{
      for (final row in personnelRows) row['id'].toString(): row,
    };

    final companyId = member.companyId;
    final workerDates = await _client
        .from('workers')
        .select('id,created_at,updated_at,employee_number,department,hire_date')
        .eq('company_id', companyId);
    final partnerDates = await _client
        .from('partner_companies')
        .select('id,created_at,updated_at')
        .eq('company_id', companyId);
    final datesById = <String, Map<String, dynamic>>{};
    for (final row in workerDates) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) datesById[id] = Map<String, dynamic>.from(row);
    }
    for (final row in partnerDates) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) datesById[id] = Map<String, dynamic>.from(row);
    }

    return rows
        .map<Map<String, dynamic>>((row) {
          final value = Map<String, dynamic>.from(row as Map);
          final id = value['id']?.toString() ?? '';
          final dates = datesById[id] ?? const <String, dynamic>{};
          final personnel = personnelByWorker[id] ?? const <String, dynamic>{};
          return {
            'id': value['id'],
            'kind': value['kind'],
            'name': value['name'] ?? '',
            'companyName': value['company_name'] ?? '',
            'phone': personnel['phone'] ?? value['phone'] ?? '',
            'email': value['email'] ?? '',
            'role': value['role'] ?? '',
            'employeeNumber':
                personnel['employeeNumber'] ?? dates['employee_number'] ?? '',
            'department': personnel['department'] ?? dates['department'] ?? '',
            'hireDate': personnel['hireDate'] ?? dates['hire_date'] ?? '',
            'notes': value['notes'] ?? '',
            'active': value['active'] == true,
            'createdAt': dates['created_at'] ?? '',
            'updatedAt': dates['updated_at'] ?? '',
            'bloodType': personnel['bloodType'] ?? '',
            'address': personnel['address'] ?? '',
            'emergencyName': personnel['emergencyName'] ?? '',
            'emergencyRelation': personnel['emergencyRelation'] ?? '',
            'emergencyPhone': personnel['emergencyPhone'] ?? '',
            'emergencyAddress': personnel['emergencyAddress'] ?? '',
            'familyComposition': personnel['familyComposition'] ?? '',
            'familyMembers': personnel['familyMembers'] is List
                ? personnel['familyMembers']
                : const <dynamic>[],
          };
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
    validatePersonnelMetadata(record);
    await _requireManagePeople();
    final companyId = await _companyId();
    final kind = record['kind']?.toString() ?? 'employee';
    if (kind == 'partnerCompany') {
      final inserted = await _client
          .from('partner_companies')
          .insert({
            'company_id': companyId,
            'name': record['name'],
            'phone': _nullable(record['phone']),
            'email': _nullable(record['email']),
            'trade_role': _nullable(record['role']),
            'notes': _nullable(record['notes']),
            'status': record['active'] == false ? 'inactive' : 'active',
          })
          .select('id')
          .single();
      return {...record, 'id': inserted['id']};
    }

    String? partnerCompanyId;
    if (kind == 'partnerWorker') {
      final companyName = record['companyName']?.toString().trim() ?? '';
      if (companyName.isEmpty) {
        throw StateError('協力会社作業員は所属会社を入力してください。');
      }
      final existing = await _client
          .from('partner_companies')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', companyName)
          .limit(1);
      if (existing.isNotEmpty) {
        partnerCompanyId = existing.first['id'] as String;
      } else {
        final created = await _client
            .from('partner_companies')
            .insert({
              'company_id': companyId,
              'name': companyName,
              'status': 'active',
            })
            .select('id')
            .single();
        partnerCompanyId = created['id'] as String;
      }
    }

    final inserted = await _client
        .from('workers')
        .insert({
          'company_id': companyId,
          'affiliation': kind == 'employee' ? 'employee' : 'partner_company',
          'partner_company_id': partnerCompanyId,
          'name': record['name'],
          'phone': _nullable(record['phone']),
          'email': _nullable(record['email']),
          'role': _nullable(record['role']),
          'employee_number': _nullable(record['employeeNumber']),
          'department': _nullable(record['department']),
          'hire_date': _nullable(record['hireDate']),
          'notes': _nullable(record['notes']),
          'status': record['active'] == false ? 'inactive' : 'active',
        })
        .select('id,employee_number')
        .single();

    final workerId = inserted['id']?.toString() ?? '';
    if (workerId.isNotEmpty) {
      await _client.rpc(
        'save_worker_personnel_profile',
        params: {
          'p_worker_id': workerId,
          'p_payload': {
            'name': record['name']?.toString() ?? '',
            'kind': kind,
            'blood_type': record['bloodType']?.toString() ?? '',
            'role': record['role']?.toString() ?? '',
            'employee_number':
                (record['employeeNumber']?.toString().trim().isNotEmpty == true)
                ? record['employeeNumber']
                : inserted['employee_number'],
            'department': record['department']?.toString() ?? '',
            'hire_date': record['hireDate']?.toString() ?? '',
            'phone': record['phone']?.toString() ?? '',
            'address': record['address']?.toString() ?? '',
            'emergency_name': record['emergencyName']?.toString() ?? '',
            'emergency_relation': record['emergencyRelation']?.toString() ?? '',
            'emergency_phone': record['emergencyPhone']?.toString() ?? '',
            'emergency_address': record['emergencyAddress']?.toString() ?? '',
            'family_composition': record['familyComposition']?.toString() ?? '',
            'family_members': record['familyMembers'] is List
                ? record['familyMembers']
                : const <dynamic>[],
          },
        },
      );
    }

    return {
      ...record,
      'id': inserted['id'],
      'employeeNumber': inserted['employee_number'] ?? '',
    };
  }

  Future<Map<String, dynamic>> savePersonnelProfile(
    Map<String, dynamic> record,
  ) async {
    validatePersonnelMetadata(record);
    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) throw StateError('社員情報を確認できません。');
    final raw = await _client.rpc(
      'save_worker_personnel_profile',
      params: {
        'p_worker_id': id,
        'p_payload': {
          'name': record['name']?.toString() ?? '',
          'kind': record['kind']?.toString() ?? 'employee',
          'blood_type': record['bloodType']?.toString() ?? '',
          'role': record['role']?.toString() ?? '',
          'employee_number': record['employeeNumber']?.toString() ?? '',
          'department': record['department']?.toString() ?? '',
          'hire_date': record['hireDate']?.toString() ?? '',
          'phone': record['phone']?.toString() ?? '',
          'address': record['address']?.toString() ?? '',
          'emergency_name': record['emergencyName']?.toString() ?? '',
          'emergency_relation': record['emergencyRelation']?.toString() ?? '',
          'emergency_phone': record['emergencyPhone']?.toString() ?? '',
          'emergency_address': record['emergencyAddress']?.toString() ?? '',
          'family_composition': record['familyComposition']?.toString() ?? '',
          'family_members': record['familyMembers'] is List
              ? record['familyMembers']
              : const <dynamic>[],
        },
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> loadPersonnelApproverSettings() async {
    final raw = await _client.rpc('worker_personnel_approver_rows');
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<void> savePersonnelApprovers(List<String> userIds) async {
    await _client.rpc(
      'set_worker_personnel_approvers',
      params: {'p_user_ids': userIds},
    );
  }

  Future<List<Map<String, dynamic>>> loadPendingPersonnelChanges() async {
    final raw = await _client.rpc('pending_worker_personnel_changes');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> decidePersonnelChange({
    required String requestId,
    required bool approve,
  }) async {
    final raw = await _client.rpc(
      'decide_worker_personnel_change',
      params: {'p_request_id': requestId, 'p_approve': approve},
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<void> delete(Map<String, dynamic> record) async {
    await _requireManagePeople();
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final kind = record['kind']?.toString() ?? 'employee';
    final table = kind == 'partnerCompany' ? 'partner_companies' : 'workers';
    await _client.from(table).delete().eq('id', id);
  }

  static void validatePersonnelMetadata(Map<String, dynamic> record) {
    final number = record['employeeNumber']?.toString().trim() ?? '';
    if (number.length > 40 || number.contains(RegExp(r'[\r\n]'))) {
      throw StateError('社員番号は改行なしの40文字以内で入力してください。');
    }
    final date = record['hireDate']?.toString().trim() ?? '';
    if (date.isNotEmpty) {
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date) {
        throw StateError('入社日を正しい日付で選択してください。');
      }
    }
  }

  static String personnelSaveError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('employee_number_duplicate') ||
        (error is PostgrestException &&
            error.code == '23505' &&
            lower.contains('employee_number'))) {
      return 'この社員番号は同じ会社で使用されています。別の番号を入力してください。';
    }
    return message.replaceFirst('Bad state: ', '');
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

