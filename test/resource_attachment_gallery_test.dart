import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGPQiJr2H4QZYAwARcwIXZ/EKIMAAAAASUVORK5CYII=');
ResourceAttachment entry(String key, String title, {String label = '表面', Future<Uint8List> Function()? load}) =>
  ResourceAttachment(label: label, path: 'same-synthetic-path', previewKey: key,
    recordTitle: title, loadBytes: load ?? () async => _png);
Widget host(ResourceAttachmentGallery gallery, ResourceAttachment selected) => MaterialApp(home: Scaffold(
  body: ResourceAttachmentThumbnail(attachment: selected, gallery: gallery, requireGalleryScope: true)));
Future<void> open(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => precacheImage(MemoryImage(_png), tester.element(find.byType(ResourceAttachmentThumbnail))));
  await tester.tap(find.byType(ResourceAttachmentThumbnail)); await tester.pumpAndSettle();
}
void main() {
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
    await tester.pumpWidget(host(gallery, entries[1])); await open(tester);
    expect(find.text('2/3'), findsOneWidget); expect(find.text('第一資格'), findsOneWidget); expect(find.text('裏面'), findsWidgets);
    expect(tester.widget<Dialog>(find.byType(Dialog)).insetPadding, EdgeInsets.zero);
    await tester.drag(find.byType(PageView), const Offset(-600, 0)); await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget); expect(find.text(List.filled(8, '次の長い書類名').join()), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0)); await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    final close = find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == '閉じる');
    final callback = tester.widget<IconButton>(close).onPressed!;
    await tester.tap(close); callback(); await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing); expect(find.byType(ResourceAttachmentThumbnail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('company A B A scope history retires a pending page and never displays late bytes', (tester) async {
    final release = Completer<Uint8List>(), changes = StreamController<Object?>.broadcast(sync: true);
    var generation = 0, company = 'A'; final initial = generation;
    final entries = [entry('a:0', '最初'), entry('b:0', '次', load: () => release.future)];
    final gallery = ResourceAttachmentGallery(source: Object(), workerId: 'w', companyId: 'A', changes: changes.stream,
      isCurrent: () => generation == initial && company == 'A', entries: entries);
    await tester.pumpWidget(host(gallery, entries.first)); await open(tester);
    await tester.drag(find.byType(PageView), const Offset(-600, 0)); await tester.pump(const Duration(milliseconds: 400));
    generation++; company = 'B'; generation++; company = 'A'; changes.add(null);
    await tester.pumpAndSettle();
    release.complete(_png); await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink()); await changes.close();
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
}
