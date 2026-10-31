import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_page.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'admin_saved_qualification_photo_submission_repository_test.dart' show Port,row,worker,actor;
class Cloud implements QualificationCloudRepository {
  final writes=<Symbol>[];
  @override
  Future<bool Function()> captureAttachmentReadScope()async=>()=>false;
  @override
  Stream<AuthState> get attachmentAuthChanges=>const Stream.empty();
  @override
  Future<Map<String,dynamic>> loadAll()async=>{
    'masters':[{'id':'master','name':'Synthetic qualification'}],
    'workers':[{'id':worker,'name':'Synthetic worker','status':'active'}],
    'qualifications':[{...row(),'qualification_master_id':'master'}],
    'supports_extra_photos':true};
  @override
  Future<bool> canManageMaster()async=>false;
  @override
  Future<bool> canManageWorkerQualifications()async=>true;
  @override
  dynamic noSuchMethod(Invocation invocation){
    writes.add(invocation.memberName);throw StateError('Unexpected operation');
  }
}
class Certificates implements QualificationCertificateRepository {
  @override
  String? get currentUserId=>actor;
  @override
  Future<bool> canManageCertificates()async=>false;
  @override
  dynamic noSuchMethod(Invocation invocation)=>throw StateError('No certificate mutation');
}
Future<void> enterFlow(WidgetTester tester)async{
  await tester.pumpAndSettle();
  await tester.tap(find.text('詳細を確認').first);await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('保存済み写真の変更申請'));
  await tester.tap(find.text('保存済み写真の変更申請'));await tester.pumpAndSettle();
  expect(find.text('残す写真・順番を選ぶ'),findsOneWidget);
}
void main(){
  for(final removeParent in [false,true]){
    testWidgets('actual management entry owns flow: ${removeParent?'parent removal':'local close'}',(tester)async{
      final cloud=Cloud(),p=Port();
      final repo=AdminSavedQualificationSubmissionRepository(p,AdminSavedQualificationTarget(row()));
      final visible=ValueNotifier(true);addTearDown(visible.dispose);
      await tester.pumpWidget(MaterialApp(home:ValueListenableBuilder<bool>(
        valueListenable:visible,builder:(_,show,__)=>show
          ? QualificationCloudPage(repository:cloud,certificateRepository:Certificates(),
              adminPhotoBuilder:(r,current,invalidations,close)=>AdminSavedQualificationPhotoPage(
                row:r,current:current,invalidations:invalidations,onClose:close,repository:repo,
                photoBuilder:(_,__)=>const Text('Synthetic retained preview')))
          : const Scaffold(body:Text('Caller removed')))));
      await enterFlow(tester);
      if(removeParent){
        await tester.tap(find.text('残す写真・順番を選ぶ'));await tester.pumpAndSettle();
        await tester.tap(find.text('選択を確認'));await tester.pumpAndSettle();
        expect(find.text('申請を送信'),findsOneWidget);
        visible.value=false;await tester.pumpAndSettle();
        expect(find.text('申請を送信'),findsNothing);
        expect(find.textContaining('2件から 2件'),findsNothing);
        expect(find.text('Caller removed'),findsOneWidget);
      }else{
        await tester.tap(find.text('閉じる'));await tester.pumpAndSettle();
        expect(find.text('従業員資格'),findsOneWidget);
        expect(find.text('残す写真・順番を選ぶ'),findsNothing);
      }
      expect(p.calls,['admin_saved_photo_capability']);expect(cloud.writes,isEmpty);
      expect(tester.takeException(),isNull);
    });
  }
}
