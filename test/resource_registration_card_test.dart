import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(home: MediaQuery(
  data: MediaQueryData(size: const Size(320, 640), textScaler: TextScaler.linear(scale)),
  child: Scaffold(body: SizedBox(width: 320, child: child))));

ResourceRegistrationCard card(List<ResourceAttachment> attachments, {String title = '健康診断書', bool registered = true}) =>
  ResourceRegistrationCard(title: title, icon: Icons.description_outlined,
    registered: registered, attachments: attachments, onAction: () {});

void main() {
  testWidgets('shared registration footer keeps full width and position for both labels', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final scale in [1.0, 1.3, 2.0]) {
      Rect? geometry;
      for (final label in ['書類を登録', '資格を登録']) {
        var presses = 0;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 640), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: const SizedBox(), bottomNavigationBar: SizedBox(width: 320,
            child: ResourceRegistrationFooter(label: label, onPressed: () => presses++))))));
        final button = find.byType(FilledButton);
        final rect = tester.getRect(button);
        geometry ??= rect;
        expect(rect, geometry);
        expect(rect.width, 288);
        expect(rect.height, greaterThanOrEqualTo(52));
        await tester.tap(button);
        expect(presses, 1);
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('document picker returns existing item only and cancels changed worker scope', (tester) async {
    var current = true;
    final edited = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async {
        final id = await chooseRegisteredDocumentRequirement(context, const [
          ResourceRegistrationOption(id: 'health', title: '健康診断書'),
          ResourceRegistrationOption(id: 'license', title: '運転免許証'),
        ], isCurrentScope: () => current);
        if (id != null) { edited.add(id); }
      }, child: const Text('書類を登録'))))));
    await tester.tap(find.text('書類を登録'));
    await tester.pumpAndSettle();
    expect(find.text('新しい書類を登録'), findsNothing);
    await tester.tap(find.text('運転免許証'));
    await tester.pumpAndSettle();
    expect(edited, ['license']);
    await tester.tap(find.text('書類を登録'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('健康診断書'));
    await tester.pumpAndSettle();
    expect(edited, ['license']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zero document has no spare thumbnail; one and two are real slots', (tester) async {
    for (var count = 0; count <= 2; count++) {
      await tester.pumpWidget(host(card(List.generate(count,
        (i) => ResourceAttachment(label: '${i + 1}', path: 'path$i')))));
      expect(find.byType(ResourceAttachmentThumbnail), findsNWidgets(count));
      if (count == 0) expect(find.text('登録なし'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('long names do not change card geometry and paired slots fit scaled 320px', (tester) async {
    for (final scale in [1.0, 1.3, 2.0]) {
      Size? initial;
      for (final title in ['資格', 'フォークリフト運転技能講習修了証明書のとても長い正式名称']) {
        await tester.pumpWidget(host(card(const [ResourceAttachment(label: '表面'),
          ResourceAttachment(label: '裏面')], title: title, registered: false), scale: scale));
        final size = tester.getSize(find.byType(ResourceRegistrationCard));
        initial ??= size;
        expect(size, initial);
        expect(find.text('表面'), findsOneWidget);
        expect(find.text('裏面'), findsOneWidget);
        expect(find.text('登録'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
  testWidgets('image opens in place and stale scope cannot open saved bytes', (tester) async {
    final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=');
    var allowed = true;
    await tester.pumpWidget(host(card([ResourceAttachment(label: '表面', path: 'front',
      loadBytes: () async => bytes, validateAccess: () async {
        if (!allowed) throw StateError('Session changed');
      })])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResourceAttachmentThumbnail));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    allowed = false;
    await tester.tap(find.byType(ResourceAttachmentThumbnail));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('再試行'), findsOneWidget);
  });
  testWidgets('a failed load can retry instead of reusing the failed future', (tester) async {
    var requests = 0;
    await tester.pumpWidget(host(card([ResourceAttachment(label: '表面', path: 'front',
      loadBytes: () { requests++; throw StateError('Unavailable'); })])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResourceAttachmentThumbnail));
    await tester.pumpAndSettle();
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('読込不可'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('retry retained after card removal cannot update a disposed thumbnail', (tester) async {
    var requests = 0;
    await tester.pumpWidget(host(card([ResourceAttachment(label: '表面', path: 'front',
      loadBytes: () async { requests++; throw StateError('Unavailable'); })])));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ResourceAttachmentThumbnail));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(const SizedBox()));
    await tester.pump();
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
}
