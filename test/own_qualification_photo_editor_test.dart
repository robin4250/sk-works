import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photo_editor.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';

void main() {
  testWidgets('upload stop keeps retained PDF reorder and removal editable', (
    tester,
  ) async {
    List<WorkerDocumentPhoto>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editWorkerDocumentPhotos(
                  context,
                  paths: ['front.pdf', 'back.pdf'],
                  signedUrl: (_) async => 'unused',
                  allowNewPhotos: false,
                  uploadNotice: '新規送信停止・保存済み編集可能',
                );
              },
              child: const Text('編集'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('編集'));
    await tester.pumpAndSettle();
    for (final button in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(button.onPressed, isNull);
    }
    for (final button in tester.widgetList<IconButton>(
      find.byTooltip('差し替え'),
    )) {
      expect(button.onPressed, isNull);
    }
    await tester.tap(find.byTooltip('前へ').last);
    await tester.pump();
    await tester.tap(find.byTooltip('写真を一覧から削除').last);
    await tester.pump();
    await tester.tap(find.text('写真を確定'));
    await tester.pumpAndSettle();
    expect(result!.map((photo) => photo.path), ['back.pdf']);
  });
}
