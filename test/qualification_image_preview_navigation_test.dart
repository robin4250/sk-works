import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photo_editor.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

final _image = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=');

void main() {
  for (final editor in [true, false]) {
    testWidgets('${editor ? 'qualification editor' : 'saved qualification card'} preview retires with its private navigator', (tester) async {
      final scope = ValueNotifier(true); addTearDown(scope.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: ValueListenableBuilder<bool>(valueListenable: scope,
          builder: (_, active, __) {
            if (!active) { return const Text('private scope removed'); }
            return Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(body: editor
                ? TextButton(onPressed: () => editWorkerDocumentPhotos(context,
                    paths: const [], useRootNavigator: false,
                    signedUrl: (_) async => throw StateError('unexpected download'),
                    initialPhotos: [WorkerDocumentPhoto.pending(_image, 'synthetic.png')]),
                    child: const Text('資格写真を確認'))
                : ResourceAttachmentThumbnail(attachment: ResourceAttachment(
                    label: '表面', path: 'synthetic-retained', loadBytes: () async => _image))),
            ));
          }),
      )));
      await tester.pumpAndSettle();
      if (editor) { await tester.tap(find.text('資格写真を確認')); await tester.pumpAndSettle(); }
      await tester.tap(find.byType(Image).first); await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      scope.value = false; await tester.pumpAndSettle();
      expect(find.text('private scope removed'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing, reason: 'a private qualification image must not escape into the root navigator');
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 568), const Size(428, 320)]) {
    testWidgets('qualification zoom preview has a visible owned close action at $size with keyboard and safe areas', (tester) async {
      tester.view.physicalSize = const Size(428, 900); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetViewInsets);
      var editorReturns = 0;
      await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 44, bottom: 34), viewPadding: const EdgeInsets.only(top: 44, bottom: 34)), child: child!), home: Scaffold(body: Builder(builder: (context) =>
          TextButton(onPressed: () async {
            await editWorkerDocumentPhotos(context, paths: const [], signedUrl: (_) async => throw StateError('unexpected download'),
              initialPhotos: [WorkerDocumentPhoto.pending(_image, 'synthetic.png')]); editorReturns++;
          }, child: const Text('資格写真を確認'))))));
      await tester.tap(find.text('資格写真を確認')); await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).first); await tester.pumpAndSettle();
      tester.view.physicalSize = size; tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      // Exercise the same panning/zoom region while its toolbar remains separate.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(InteractiveViewer)));
      await gesture.moveBy(const Offset(40, 20)); await gesture.up(); await tester.pump();
      expect(viewer.maxScale, greaterThan(1));
      final close = find.byTooltip('閉じる'); expect(close, findsOneWidget);
      final rect = tester.getRect(close);
      expect(rect.top, greaterThanOrEqualTo(44)); expect(rect.bottom, lessThanOrEqualTo(size.height - 34));
      final action = tester.widget<IconButton>(close).onPressed!;
      action(); action(); // A retained repeated callback must never pop the editor behind this preview.
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing); expect(find.text('登録写真 1枚'), findsOneWidget);
      expect(editorReturns, 0); expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
