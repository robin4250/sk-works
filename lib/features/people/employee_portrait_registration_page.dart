import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'employee_portrait_repository.dart';
import 'people_cloud_repository.dart';
import 'worker_document_photo_editor.dart';
import 'worker_document_photos.dart';
import 'worker_document_page.dart';

class EmployeePortraitRegistrationPage extends StatefulWidget {
  const EmployeePortraitRegistrationPage({super.key,required this.privacySession,
    required this.workerId,required this.companyName,this.repositoryOverride,this.photoPicker});
  final PersonnelPrivacySession privacySession;
  final String workerId,companyName;
  @visibleForTesting final EmployeePortraitRepository? repositoryOverride;
  @visibleForTesting final Future<List<WorkerDocumentPhoto>?> Function(BuildContext)? photoPicker;
  @override State<EmployeePortraitRegistrationPage> createState()=>_EmployeePortraitRegistrationPageState();
}
class _EmployeePortraitRegistrationPageState extends State<EmployeePortraitRegistrationPage> {
  EmployeePortraitRepository? _repository;
  EmployeePortraitDraft? _draft;
  WorkerDocumentPhoto? _photo;
  bool _busy=true,_revoked=false,_missingRequirement=false;
  int _generation=0;
  String? _error;
  @override void initState(){super.initState();widget.privacySession.addListener(_scopeChanged);unawaited(_load());}
  void _scopeChanged(){
    final session=widget.privacySession;
    if(session.revoked || !session.active || (session.snapshot!=null && !session.snapshot!.canManage)){
      _generation++;_revoked=true;
      if(mounted){setState((){_draft=null;_photo=null;_busy=false;_error='社員情報の権限を再確認してください。画面を閉じて開き直してください。';});}
    }
  }
  bool _live(int generation)=>mounted && !_revoked && generation==_generation;
  String _message(Object error)=>error is EmployeePortraitRequirementMissing?error.toString():error is StateError?error.message.toString():'写真を保存できませんでした。元の登録を再読み込みして確認してください。';
  Future<void> _load() async {
    final generation=++_generation;
    try{
      final repository=_repository??=widget.repositoryOverride??EmployeePortraitRepository(privacySession:widget.privacySession,workerId:widget.workerId);
      final draft=await repository.load();if(!_live(generation)){return;}
      setState((){_draft=draft;_busy=false;_error=null;_missingRequirement=false;});
    }catch(error){if(_live(generation)){setState((){_busy=false;_error=_message(error);_missingRequirement=error is EmployeePortraitRequirementMissing;});}}
  }
  Future<void> _settings() async {
    if(_busy || _revoked || !_missingRequirement){return;}
    final generation=_generation;setState(()=>_busy=true);
    try{
      await _repository!.verifySettingsAccess();if(!mounted || !_live(generation)){return;}
      await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>const WorkerDocumentPage(view:WorkerDocumentView.settings)));
      if(!_live(generation)){return;}
      await _load();
    }catch(error){if(_live(generation)){setState(()=>_error=_message(error));}}
    finally{if(_live(generation)){setState(()=>_busy=false);}}
  }
  Future<void> _pick() async {
    if(_busy || _revoked || _draft==null){return;}
    final generation=_generation;setState(()=>_busy=true);
    try{
      final values=await (widget.photoPicker?.call(context)??editWorkerDocumentPhotos(context,
        paths:const [],signedUrl:(_)=>Future<String>.error(StateError('保存済み写真は変更しません。')),
        uploadNotice:'顔写真画像を1枚選択してください。元の写真は保持します。'));
      if(!_live(generation) || values==null){return;}
      if(values.length!=1 || values.single.path!=null || values.single.bytes==null ||
        values.single.bytes!.isEmpty || values.single.bytes!.length>6*1024*1024 ||
        !RegExp(r'\.(jpg|jpeg|png|heic|heif)$',caseSensitive:false).hasMatch(values.single.filename??'')){throw StateError('6MiB以内の顔写真画像を1枚選択してください。PDFは登録できません。');}
      final codec=await ui.instantiateImageCodec(values.single.bytes!);
      try{final frame=await codec.getNextFrame();frame.image.dispose();}finally{codec.dispose();}
      if(!_live(generation)){return;}
      setState((){_photo=values.single;_error=null;});
    }catch(error){if(_live(generation)){setState(()=>_error=_message(error));}}
    finally{if(_live(generation)){setState(()=>_busy=false);}}
  }
  Future<void> _save() async {
    if(_busy || _revoked || _draft==null || _photo==null){return;}
    final generation=_generation;setState(()=>_busy=true);
    try{
      await _repository!.save(_draft!,_photo!);if(!mounted || !_live(generation)){return;}
      _photo=null;Navigator.of(context).pop(true);
    }catch(error){if(_live(generation)){setState(()=>_error=_message(error));}}
    finally{if(_live(generation)){setState(()=>_busy=false);}}
  }
  @override void dispose(){_generation++;_photo=null;widget.privacySession.removeListener(_scopeChanged);unawaited(_repository?.dispose()??Future<void>.value());super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('社員の顔写真')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Text(widget.companyName),const SizedBox(height:12),
      const Text('選択した社員の顔写真を登録します。以前の写真は削除せず保持します。登録後、原本確認は別途必要です。'),
      if(_busy)const LinearProgressIndicator(),
      if(_error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_error!,key:const Key('employee-portrait-error'))),
      if(_missingRequirement)OutlinedButton(key:const Key('employee-portrait-settings'),onPressed:_busy||_revoked?null:_settings,child:const Text('必要書類設定で顔写真項目を登録')),
      if(_draft!=null)Text('必要書類：${_draft!.requirement['name']}'),
      if(_photo?.bytes!=null)Image.memory(_photo!.bytes!,height:200,fit:BoxFit.contain,errorBuilder:(_,_,_)=>const Text('選択した写真を表示できません。')),
      const SizedBox(height:16),
      OutlinedButton.icon(key:const Key('employee-portrait-pick'),onPressed:_busy||_revoked||_draft==null?null:_pick,icon:const Icon(Icons.add_a_photo_outlined),label:const Text('顔写真を選択')),
      FilledButton(key:const Key('employee-portrait-save'),onPressed:_busy||_revoked||_draft==null||_photo==null?null:_save,child:const Text('この社員の顔写真を保存')),
      TextButton(onPressed:_busy?null:()=>Navigator.of(context).pop(false),child:const Text('キャンセル')),
    ]),
  );
}
