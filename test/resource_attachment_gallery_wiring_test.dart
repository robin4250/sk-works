import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

final _png=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGPQiJr2H4QZYAwARcwIXZ/EKIMAAAAASUVORK5CYII=');
late StreamController<AuthState> _changes;
class _PictureClient implements HttpClient {
  @override Future<HttpClientRequest> getUrl(Uri url) async {
    expect(url.host,'synthetic.invalid'); return _PictureRequest();
  }
  @override void close({bool force=false}) {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _PictureRequest implements HttpClientRequest {
  @override bool followRedirects=false;
  @override Future<HttpClientResponse> close() async => _PictureResponse();
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _PictureResponse extends Stream<List<int>> implements HttpClientResponse {
  @override int get statusCode=>200;
  @override StreamSubscription<List<int>> listen(void Function(List<int>)? onData,{Function? onError,void Function()? onDone,bool? cancelOnError}) =>
    Stream<List<int>>.value(_png).listen(onData,onError:onError,onDone:onDone,cancelOnError:cancelOnError);
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
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
  _Qualifications({this.rows = _qualifications});
  final List<Map<String,dynamic>> rows;
  final pending = <Future<Map<String,dynamic>>>[];
  @override String? get currentUserId => 'actor';
  @override Future<bool Function()> captureAttachmentReadScope() async => () => true;
  @override Stream<AuthState> get attachmentAuthChanges => _changes.stream;
  @override Future<bool> canManageMaster() async => false;
  @override Future<bool> canManageWorkerQualifications() async => false;
  @override Future<Map<String,dynamic>> loadOwnQualificationWorkspace() async => {'worker':_worker,'masters':_masters,'qualifications':rows};
  @override Future<Map<String,dynamic>> loadAll() async {
    if (pending.isNotEmpty) { return pending.removeAt(0); }
    return {'workers':[_worker],'masters':_masters,'qualifications':rows};
  }
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
  @override Stream<Object?> get attachmentAuthChanges => _changes.stream;
  @override Future<Map<String,List<Map<String,dynamic>>>> loadAll() async => {
    'workers':[_worker],'requirements':_requirements,'statuses':_statuses,'exemptions':[]};
  @override Future<String> signedUrl(String path) async => 'https://synthetic.invalid/$path';
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _ManagedDocuments extends WorkerDocumentRepository {
  _ManagedDocuments(super.client) : super.forTesting();
  @override String? get actorId => 'actor';
  @override Future<bool Function()> captureAttachmentReadScope() async => () => true;
  @override Stream<AuthState> get attachmentAuthChanges => _changes.stream;
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
Future<void> verifyLiveTitles(WidgetTester tester,String title,bool qualifications) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final card=find.byWidgetPredicate((widget)=>widget is ResourceRegistrationCard && widget.title==title).first;
  final thumb=find.descendant(of:card,matching:find.byType(ResourceAttachmentThumbnail)).first;
  for(var frame=0;frame<30 && tester.widgetList<RawImage>(find.descendant(of:thumb,matching:find.byType(RawImage))).any((image)=>image.image==null);frame++) {
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await tester.pump(const Duration(milliseconds:16));
  }
  expect(tester.widget<RawImage>(find.descendant(of:thumb,matching:find.byType(RawImage))).image,isNotNull);
  await tester.pumpAndSettle(); await tester.ensureVisible(thumb);await tester.tap(thumb);await tester.pumpAndSettle();
  final count=qualifications?4:3;
  expect(find.descendant(of:find.byType(AppBar).last,matching:find.text(title)),findsOneWidget);
  expect(find.text('1/$count'),findsOneWidget);
  for(var i=1;i<count;i++) { await tester.drag(find.byType(PageView),Offset(-tester.getSize(find.byType(PageView)).width*.75,0));await tester.pumpAndSettle(); }
  expect(find.text('$count/$count'),findsOneWidget);
  expect(find.descendant(of:find.byType(AppBar).last,matching:find.text(qualifications?'合成資格B':'合成書類B')),findsOneWidget);
  await tester.tap(find.byWidgetPredicate((widget)=>widget is IconButton && widget.tooltip=='閉じる'));await tester.pumpAndSettle();
  expect(find.byType(PageView),findsNothing);
}
void main() {
  setUp(() { TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed);_changes=StreamController<AuthState>.broadcast(); });
  tearDown(() async { await _changes.close(); });
  testWidgets('own qualifications wire full saved same-worker names and ordinal identities beyond search results',(tester) async {
    await HttpOverrides.runZoned(() async {
    await tester.pumpWidget(MaterialApp(home:OwnQualificationRegistrationPage(repository:_Qualifications()))); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true);
    await tester.enterText(find.byType(TextField).first,'合成資格A'); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true); await verifyLiveTitles(tester,'合成資格A',true);expect(tester.takeException(),isNull);
    },createHttpClient:(_) => _PictureClient());
  });
  testWidgets('managed qualifications wire same-worker gallery across records without foreign employee paths',(tester) async {
    await HttpOverrides.runZoned(() async {
    await tester.pumpWidget(MaterialApp(home:QualificationCloudPage(repository:_Qualifications(),certificateRepository:_Certificates()))); await tester.pumpAndSettle();
    verify(tester,'合成資格A',true); await verifyLiveTitles(tester,'合成資格A',true);expect(tester.takeException(),isNull);
    },createHttpClient:(_) => _PictureClient());
  });
  testWidgets('own documents wire one and paired slots across saved document names',(tester) async {
    await HttpOverrides.runZoned(() async {
    await tester.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:_OwnDocuments()))); await tester.pumpAndSettle();
    verify(tester,'合成書類A',false); await verifyLiveTitles(tester,'合成書類A',false);expect(tester.takeException(),isNull);
    },createHttpClient:(_) => _PictureClient());
  });
  testWidgets('managed documents wire same worker and company gallery across document scope filters',(tester) async {
    await HttpOverrides.runZoned(() async {
    final client=SupabaseClient('https://synthetic.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false));addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(home:WorkerDocumentPage(view:WorkerDocumentView.workers,repositoryOverride:_ManagedDocuments(client))));await tester.pumpAndSettle();
    await tester.tap(find.text('合成社員A'));await tester.pumpAndSettle();verify(tester,'合成書類A',false);await verifyLiveTitles(tester,'合成書類A',false);expect(tester.takeException(),isNull);
    },createHttpClient:(_) => _PictureClient());
  });
  testWidgets('newer qualification response wins and a stale load cannot retire the current gallery',(tester) async {
    await HttpOverrides.runZoned(() async {
    final repository=_Qualifications();
    await tester.pumpWidget(MaterialApp(home:QualificationCloudPage(repository:repository,certificateRepository:_Certificates())));await tester.pumpAndSettle();
    final oldGallery=tester.widgetList<ResourceRegistrationCard>(find.byType(ResourceRegistrationCard)).first.gallery!;
    final old=Completer<Map<String,dynamic>>(),fresh=Completer<Map<String,dynamic>>();repository.pending.addAll([old.future,fresh.future]);
    final reload=tester.widget<IconButton>(find.byWidgetPredicate((widget)=>widget is IconButton && widget.tooltip=='再読み込み')).onPressed!;
    reload(); reload(); await tester.pump(); expect(oldGallery.isCurrent(),isFalse);
    fresh.complete({'workers':[_worker],'masters':[{'id':'m1','name':'最新資格A'},_masters[1]],'qualifications':_qualifications});await tester.pumpAndSettle();
    final current=tester.widgetList<ResourceRegistrationCard>(find.byType(ResourceRegistrationCard)).firstWhere((card)=>card.title=='最新資格A').gallery!;
    expect(current.isCurrent(),isTrue);
    old.complete({'workers':[_worker],'masters':_masters,'qualifications':_qualifications});await tester.pumpAndSettle();
    expect(find.text('最新資格A'),findsOneWidget);expect(current.isCurrent(),isTrue);expect(tester.takeException(),isNull);
    },createHttpClient:(_) => _PictureClient());
  });
  testWidgets('missing or foreign company metadata cannot fall back to an unscoped gallery',(tester) async {
    await HttpOverrides.runZoned(() async {
    for(final company in [null,'company-B']) {
      final repository=_Qualifications(rows:[{..._qualifications.first,'company_id':company}]);
      await tester.pumpWidget(MaterialApp(home:OwnQualificationRegistrationPage(key:ValueKey(company),repository:repository)));await tester.pumpAndSettle();
      final card=tester.widget<ResourceRegistrationCard>(find.byType(ResourceRegistrationCard));
      expect(card.requireGalleryScope,isTrue);expect(card.gallery,isNull);expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    },createHttpClient:(_) => _PictureClient());
  });

}
