import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGPQiJr2H4QZYAwARcwIXZ/EKIMAAAAASUVORK5CYII=');
ResourceAttachment entry(String key, String title, {String label = '表面', Future<Uint8List> Function()? load}) =>
  ResourceAttachment(label: label, path: 'same-synthetic-path', previewKey: key,
    recordTitle: title, loadBytes: load ?? () async => _png);
Widget host(ResourceAttachmentGallery gallery, ResourceAttachment selected, {double scale=1}) => MaterialApp(
  builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),home: Scaffold(
  body: ResourceAttachmentThumbnail(attachment: selected, gallery: gallery, requireGalleryScope: true)));
Future<void> open(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
  for (var frame=0;frame<30 && tester.widgetList<RawImage>(find.byType(RawImage)).any((image)=>image.image==null);frame++) {
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await tester.pump(const Duration(milliseconds:16));
  }
  await tester.tap(find.byType(ResourceAttachmentThumbnail)); await tester.pumpAndSettle();
  for(var frame=0;frame<30 && tester.widgetList<RawImage>(find.descendant(of:find.byType(PageView),matching:find.byType(RawImage))).any((image)=>image.image==null);frame++) {
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await tester.pump(const Duration(milliseconds:16));
  }
}
void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  test('snapshot is immutable, preserves duplicate paths and rejects duplicate record anchors', () {
    final entries = [entry('a:0', '資格A'), entry('b:0', '資格B')];
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'c', isCurrent: () => true, entries: entries);
    entries.clear(); expect(gallery.entries, hasLength(2));
    expect(gallery.indexOf(gallery.entries[1]), 1);
    expect(() => ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'c', isCurrent: () => true,
      entries: [entry('a:0', 'A'), entry('a:0', 'B')]), throwsArgumentError);
  });
  testWidgets('fullscreen opens selected record occurrence and swipe updates real name, side and count', (tester) async {
    final entries = [entry('a:0', '第一資格'), entry('a:1', '第一資格', label: '裏面'), entry('b:0', List.filled(8, '次の長い書類名').join(), label: '1')];
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'c', isCurrent: () => true, entries: entries);
    tester.view.physicalSize=const Size(320,568);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(gallery, entries[1],scale:2)); await open(tester);
    expect(find.text('2/3'), findsOneWidget); expect(find.text('第一資格'), findsOneWidget); expect(find.text('裏面'), findsWidgets);
    expect(tester.widget<Dialog>(find.byType(Dialog)).insetPadding, EdgeInsets.zero);
    await tester.drag(find.byType(PageView), const Offset(-600, 0)); await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget); expect(find.text(List.filled(8, '次の長い書類名').join()), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0)); await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    final close = find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '閉じる');
    final rect=tester.getRect(close);expect(rect.right,lessThanOrEqualTo(320));expect(rect.bottom,lessThanOrEqualTo(568));
    final callback = tester.widget<IconButton>(close).onPressed!;
    await tester.tap(close); callback(); await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing); expect(find.byType(ResourceAttachmentThumbnail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('company A B A scope history retires a pending page and never displays late bytes', (tester) async {
    final release = Completer<Uint8List>(), signal = ValueNotifier(0);
    var generation = 0, company = 'A'; final initial = generation;
    final entries = [entry('a:0', '最初'), entry('b:0', '次', load: () => release.future)];
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'A', signal: signal,
      isCurrent: () => generation == initial && company == 'A', entries: entries);
    await tester.pumpWidget(host(gallery, entries.first)); await open(tester);
    await tester.drag(find.byType(PageView), const Offset(-600, 0)); await tester.pump(const Duration(milliseconds: 400));
    generation++; company = 'B'; generation++; company = 'A'; signal.value++;
    await tester.pumpAndSettle();
    release.complete(_png); await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); signal.dispose();
  });
  testWidgets('private parent destruction removes its own fullscreen gallery', (tester) async {
    final active = ValueNotifier(true); final attachment = entry('a:0', '本人書類');
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'c', isCurrent: () => active.value, entries: [attachment]);
    await tester.pumpWidget(MaterialApp(home: ValueListenableBuilder<bool>(valueListenable: active,
      builder: (_, present, __) => present ? Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) =>
        Scaffold(body: ResourceAttachmentThumbnail(attachment: attachment, gallery: gallery)))) : const Text('private scope gone'))));
    await open(tester); active.value = false; await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing); expect(find.text('private scope gone'), findsOneWidget);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox.shrink()); active.dispose();
  });
  testWidgets('auth history stream retires already rendered bytes immediately',(tester) async {
    final changes=StreamController<Object?>.broadcast(sync:true);var allowed=true;
    final attachment=entry('a:0','資格');final gallery=ResourceAttachmentGallery(source:Object(),workerId:'w',companyId:'c',
      changes:changes.stream,isCurrent:()=>allowed,entries:[attachment]);
    await tester.pumpWidget(host(gallery,attachment));await open(tester);
    allowed=false;changes.add(null);await tester.pumpAndSettle();
    expect(find.byType(PageView),findsNothing);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());await changes.close();
  });

  testWidgets('retained PDF builder rejects original bytes after the gallery scope is retired',(tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const channel=MethodChannel('net.nfet.printing');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async => call.method=='printingInfo'?{'canRaster':false}:null);
    final document=pw.Document()..addPage(pw.Page(build:(_)=>pw.Text('Synthetic original PDF')));
    final pdf=await document.save();var allowed=true;final changes=StreamController<Object?>.broadcast(sync:true);
    final attachment=ResourceAttachment(label:'1',path:'synthetic.pdf',previewKey:'pdf:0',recordTitle:'合成PDF',loadBytes:()async=>pdf);
    final gallery=ResourceAttachmentGallery(source:Object(),workerId:'w',companyId:'c',isCurrent:()=>allowed,changes:changes.stream,entries:[attachment]);
    try {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ResourceAttachmentThumbnail(attachment:attachment,gallery:gallery,
        rasterizeFirstPage:(_)async=>_png))));await tester.pumpAndSettle();
      await tester.tap(find.byType(ResourceAttachmentThumbnail));
      for(var frame=0;frame<20&&find.byType(PdfPreview).evaluate().isEmpty;frame++){await tester.pump(const Duration(milliseconds:16));}
      final callback=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
      expect(await callback(PdfPageFormat.a4),pdf);
      allowed=false;changes.add(null);await tester.pumpAndSettle();
      await expectLater(callback(PdfPageFormat.a4),throwsStateError);
      expect(find.byType(PdfPreview),findsNothing);expect(tester.takeException(),isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());await changes.close();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    }
  });

  for(final resumeBeforeReply in [false,true]) {
    testWidgets('pending open cannot cross background history resume-before-reply=$resumeBeforeReply',(tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final release=Completer<Uint8List>();final attachment=entry('a:0','合成資格',load:()=>release.future);
      final gallery=ResourceAttachmentGallery(source:Object(),workerId:'w',companyId:'c',isCurrent:()=>true,entries:[attachment]);
      await tester.pumpWidget(host(gallery,attachment));await tester.pump();
      await tester.tap(find.byType(ResourceAttachmentThumbnail));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if(resumeBeforeReply){tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);}
      release.complete(_png);await tester.pump();
      expect(find.byType(PageView),findsNothing);expect(find.byType(InteractiveViewer),findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
      expect(find.byType(PageView),findsNothing);expect(find.byType(InteractiveViewer),findsNothing);expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

}
