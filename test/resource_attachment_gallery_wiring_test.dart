import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_page.dart';
import 'package:sk_works/features/qualifications/own_qualification_registration_page.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

const _worker = {'id':'worker-A','company_id':'company-A','name':'合成社員A','status':'active'};
const _masters = [{'id':'m1','name':'合成資格A'},{'id':'m2','name':'合成資格B'}];
const _qualifications = [
  {'id':'q1','company_id':'company-A','worker_id':'worker-A','qualification_master_id':'m1','attachment_path':'same.png','attachment_back_path':'same.png','attachment_extra_paths':['extra.png']},
  {'id':'q2','company_id':'company-A','worker_id':'worker-A','qualification_master_id':'m2','attachment_path':'same.png'},
  {'id':'foreign','company_id':'company-A','worker_id':'worker-B','qualification_master_id':'m2','attachment_path':'never.png'},
];
const _requirements = [
  {'id':'d1','company_id':'company-A','name':'合成書類A','is_active':true,'scope':'internal'},
  {'id':'d2','company_id':'company-A','name':'合成書類B','is_active':true,'scope':'upstream'},
];
const _statuses = [
  {'id':'s1','company_id':'company-A','worker_id':'worker-A','requirement_id':'d1','status':'submitted','attachment_path':'same.png','attachment_paths':['same.png','back.png']},
  {'id':'s2','company_id':'company-A','worker_id':'worker-A','requirement_id':'d2','status':'submitted','attachment_path':'same.png'},
  {'id':'foreign','company_id':'company-A','worker_id':'worker-B','requirement_id':'d1','status':'submitted','attachment_path':'never.png'},
];
class _Qualifications implements QualificationCloudRepository {
  @override String? get currentUserId => 'actor';
  @override Future<bool Function()> captureAttachmentReadScope() async => () => true;
  @override Stream<AuthState> get attachmentAuthChanges => const Stream.empty();
  @override Future<bool> canManageMaster() async => false;
  @override Future<bool> canManageWorkerQualifications() async => false;
  @override Future<Map<String,dynamic>> loadOwnQualificationWorkspace() async => {'worker':_worker,'masters':_masters,'qualifications':_qualifications};
  @override Future<Map<String,dynamic>> loadAll() async => {'workers':[_worker],'masters':_masters,'qualifications':_qualifications};
  @override Future<String> createOwnQualificationPhotoUrl({required String qualificationId,required String storagePath}) async => 'https://synthetic.invalid/$storagePath';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Certificates implements QualificationCertificateRepository {
  @override String? get currentUserId => 'actor';
  @override Future<bool> canManageCertificates() async => false;
  @override Future<String> createSignedUrl(String storagePath) async => 'https://synthetic.invalid/$storagePath';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _OwnDocuments implements OwnDocumentGalleryGateway {
  @override bool get photoEditingAvailable => true;
  @override Future<bool Function()> captureAttachmentReadScope() async => () => true;
  @override Stream<Object?> get attachmentAuthChanges => const Stream.empty();
  @override Future<Map<String,List<Map<String,dynamic>>>> loadAll() async => {
    'workers':[_worker],'requirements':_requirements,'statuses':_statuses,'exemptions':[]};
  @override Future<String> signedUrl(String path) async => 'https://synthetic.invalid/$path';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _ManagedDocuments extends WorkerDocumentRepository {
  _ManagedDocuments(super.client) : super.forTesting();
  @override String? get actorId => 'actor';
  @override Future<bool Function()> captureAttachmentReadScope() async => () => true;
  @override Stream<AuthState> get attachmentAuthChanges => const Stream.empty();
  @override Future<bool> canManageRequirements() async => false;
  @override Future<bool> canManageStatuses() async => false;
  @override Future<Map<String,List<Map<String,dynamic>>>> loadAll({bool includeHiddenRequirements=false}) async => {
    'workers':[_worker],'requirements':_requirements,'statuses':_statuses,'exemptions':[]};
  @override Future<String> createSignedAttachmentUrl(String path) async => 'https://synthetic.invalid/$path';
}
void verify(WidgetTester tester, String title, bool qualifications) {
  final card = tester.widgetList<ResourceRegistrationCard>(find.byType(ResourceRegistrationCard)).firstWhere((card)=>card.title==title);
  expect(card.requireGalleryScope,isTrue); final gallery=card.gallery!;
  expect(gallery.workerId,'worker-A'); expect(gallery.companyId,'company-A'); expect(gallery.isCurrent(),isTrue);
  expect(gallery.entries.map((entry)=>entry.recordTitle).toSet(), qualifications ? {'合成資格A','合成資格B'} : {'合成書類A','合成書類B'});
  expect(gallery.entries.any((entry)=>entry.path=='never.png'),isFalse);
  expect(gallery.entries.length,qualifications ? 4 : 3);
  expect(gallery.entries.map((entry)=>entry.previewKey).toSet().length,gallery.entries.length);
  expect(gallery.entries.where((entry)=>entry.path=='same.png').length,qualifications ? 3 : 2);
  expect(gallery.entries.last.recordTitle,qualifications ? '合成資格B' : '合成書類B');
  expect(gallery.indexOf(card.attachments.first),0);
}
void main() {
  testWidgets('own qualifications wire full saved same-worker names and ordinal identities beyond search results',(tester) async {
    await tester.pumpWidget(MaterialApp(home:OwnQualificationRegistrationPage(repository:_Qualifications()))); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true);
    await tester.enterText(find.byType(TextField).first,'合成資格A'); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true); expect(tester.takeException(),isNull);
  });
  testWidgets('managed qualifications wire same-worker gallery across records without foreign employee paths',(tester) async {
    await tester.pumpWidget(MaterialApp(home:QualificationCloudPage(repository:_Qualifications(),certificateRepository:_Certificates()))); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true); expect(tester.takeException(),isNull);
  });
  testWidgets('own documents wire one and paired slots across saved document names',(tester) async {
    await tester.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:_OwnDocuments()))); await tester.pumpAndSettle();
    verify(tester,'合成書類A',false); expect(tester.takeException(),isNull);
  });
  testWidgets('managed documents wire same worker and company gallery across document scope filters',(tester) async {
    final client=SupabaseClient('https://synthetic.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false));addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(home:WorkerDocumentPage(view:WorkerDocumentView.workers,repositoryOverride:_ManagedDocuments(client))));await tester.pumpAndSettle();
    await tester.tap(find.text('合成社員A'));await tester.pumpAndSettle();verify(tester,'合成書類A',false);expect(tester.takeException(),isNull);
  });
}
