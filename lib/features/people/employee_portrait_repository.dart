import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'people_cloud_repository.dart';
import 'worker_document_repository.dart';
import 'worker_document_photos.dart';

class EmployeePortraitRequirementMissing implements Exception {
  const EmployeePortraitRequirementMissing();
  @override String toString()=>'必要書類設定で「顔写真」を社内用・任意・期限なしの項目として登録してください。';
}

class EmployeePortraitDraft {
  const EmployeePortraitDraft({required this.requirement, required this.row, required this.paths});
  final Map<String,dynamic> requirement;
  final Map<String,dynamic>? row;
  final List<String> paths;
}

/// Selected employee/company only. Reuses the managed-document upload/CAS API.
/// Existing and uncertain objects are never overwritten or deleted.
class EmployeePortraitRepository {
  EmployeePortraitRepository._(this.privacySession,this.workerId,this._client,this._documents) {
    final captured=_client.auth.currentSession;
    if(captured==null || captured.isExpired || captured.user.id!=privacySession.actor){throw const PersonnelScopeChanged();}
    _token=captured.accessToken;
    var first=true;
    _auth=_client.auth.onAuthStateChange.listen((event){
      final replay=first && identical(event.session,captured) &&
        [AuthChangeEvent.initialSession,AuthChangeEvent.signedIn,AuthChangeEvent.tokenRefreshed].contains(event.event);
      first=false;if(!replay){_invalid=true;}
    },onError:(Object _){_invalid=true;},onDone:(){_invalid=true;});
  }
  factory EmployeePortraitRepository({required PersonnelPrivacySession privacySession,required String workerId}) {
    final documents=WorkerDocumentRepository.maybeCreate();
    if(documents==null || !SupabaseBackend.isInitialized){throw const PersonnelScopeChanged();}
    return EmployeePortraitRepository._(privacySession,workerId,SupabaseBackend.client,documents);
  }
  @visibleForTesting
  factory EmployeePortraitRepository.forTesting({required PersonnelPrivacySession privacySession,required String workerId,
    required SupabaseClient client,required WorkerDocumentRepository documents})=>EmployeePortraitRepository._(privacySession,workerId,client,documents);
  final PersonnelPrivacySession privacySession;
  final String workerId;
  final SupabaseClient _client;
  final WorkerDocumentRepository _documents;
  late final String _token;
  StreamSubscription<AuthState>? _auth;
  bool _invalid=false;
  int? _lease;
  void _live(){
    final lease=_lease;
    if(_invalid || lease==null || _client.auth.currentSession?.accessToken!=_token ||
      _client.auth.currentSession?.isExpired!=false || _client.auth.currentUser?.id!=privacySession.actor){throw const PersonnelScopeChanged();}
    privacySession.verify(lease);
  }
  Future<void> _authorize() async {
    if(_invalid){throw const PersonnelScopeChanged();}
    final rows=await privacySession.read(workerIds:{workerId});
    _lease=privacySession.epoch;_live();
    if(privacySession.snapshot?.canManage!=true || rows.single['personnelBasicOnly']==true){throw StateError('社員の顔写真を変更する権限がありません。');}
    final member=await _documents.membership();_live();
    if(member.companyId!=privacySession.company || !await _documents.canManageStatuses()){throw const PersonnelScopeChanged();}
    _live();
  }
  static String _name(Object? name)=>name.toString().replaceAll(RegExp(r'[\s　]+'),'');
  Future<EmployeePortraitDraft> load() async {
    await _authorize();
    final data=await _documents.loadAll();_live();
    if(!_documents.photoEditingAvailable){throw StateError(WorkerDocumentRepository.photoPreparationMessage);}
    final workers=(data['workers']??[]).where((row)=>row['id']==workerId && row['status']=='active').toList();
    if(workers.length!=1){throw StateError('在籍中の対象社員を確認してください。');}
    final requirements=(data['requirements']??[]).where((row)=>row['company_id']==privacySession.company && row['is_active']==true &&
      row['archived_at']==null && ['顔写真','証明写真','身分証明写真'].contains(_name(row['name']))).toList();
    requirements.sort((a,b){
      int priority(Map<String,dynamic> r)=>['internal','both'].contains(r['scope'])?0:1;
      final scope=priority(a).compareTo(priority(b));if(scope!=0){return scope;}
      final order=(a['sort_order'] as num? ?? 0).compareTo(b['sort_order'] as num? ?? 0);
      return order!=0?order:a['id'].toString().compareTo(b['id'].toString());
    });
    if(requirements.isEmpty){throw const EmployeePortraitRequirementMissing();}
    final requirement=Map<String,dynamic>.unmodifiable(requirements.first);
    final rows=(data['statuses']??[]).where((row)=>row['worker_id']==workerId && row['requirement_id']==requirement['id']).toList();
    if(rows.length>1){throw StateError('元の顔写真登録を確認できません。');}
    final row=rows.isEmpty?null:Map<String,dynamic>.unmodifiable(rows.single);
    return EmployeePortraitDraft(requirement:requirement,row:row,paths:List.unmodifiable(workerDocumentPaths(row)));
  }
  Future<void> verifySettingsAccess() async {await _authorize();if(!await _documents.canManageRequirements()){throw const PersonnelScopeChanged();}_live();}
  Future<String> signedUrl(String path) async {await _authorize();final draft=await load();_live();if(!draft.paths.contains(path)){throw const PersonnelScopeChanged();}final value=await _documents.createSignedAttachmentUrl(path);_live();return value;}
  Future<void> save(EmployeePortraitDraft original,WorkerDocumentPhoto photo) async {
    final name=photo.filename?.toLowerCase()??'',bytes=photo.bytes;
    if(photo.path!=null || bytes==null || bytes.isEmpty || bytes.length>6*1024*1024 ||
      !RegExp(r'\.(jpg|jpeg|png|heic|heif)$').hasMatch(name)){throw StateError('6MiB以内の顔写真画像を1枚選択してください。');}
    final detached=WorkerDocumentPhoto.pending(Uint8List.fromList(bytes),photo.filename!);
    final fresh=await load();_live();
    if(fresh.requirement['id']!=original.requirement['id'] || fresh.row?['id']!=original.row?['id'] || fresh.row?['updated_at']!=original.row?['updated_at'] ||
      !listEquals(fresh.paths,original.paths)){throw StateError('元の登録が更新されています。再読み込みしてください。');}
    if(fresh.paths.length>=20){throw StateError('元の写真を保持するため追加できません。管理者が登録履歴を確認してください。');}
    await _documents.saveManagedDocumentPhotos(workerId:workerId,requirementId:fresh.requirement['id'] as String,
      status:'submitted',expiresAt:DateTime.tryParse(fresh.row?['expires_at']?.toString()??''),originalVerified:false,
      notes:fresh.row?['notes']?.toString()??'',photos:[detached,...fresh.paths.map(WorkerDocumentPhoto.saved)],expectedRow:fresh.row,requireScope:_live);
    _live();await load();_live();
  }
  Future<void> dispose() async {_invalid=true;await _auth?.cancel();}
}
