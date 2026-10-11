import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photo_editor.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';

void main() {
  testWidgets(
    'reopening an unsaved worker draft preserves every pending photo',
    (tester) async {
      final first = WorkerDocumentPhoto.pending(
        Uint8List.fromList([1]),
        'front.jpg',
      );
      final second = WorkerDocumentPhoto.pending(
        Uint8List.fromList([2]),
        'back.jpg',
      );
      var draft = <WorkerDocumentPhoto>[first, second];
      var signedReads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  final edited = await editWorkerDocumentPhotos(
                    context,
                    paths: const [],
                    initialPhotos: draft,
                    signedUrl: (path) async {
                      signedReads++;
                      return path;
                    },
                  );
                  if (edited != null) draft = edited;
                },
                child: const Text('登録写真を編集'),
              ),
            ),
          ),
        ),
      );
      for (var open = 0; open < 2; open++) {
        await tester.tap(find.text('登録写真を編集'));
        await tester.pumpAndSettle();
        expect(find.text('登録写真 2枚'), findsOneWidget);
        expect(find.text('1枚目（未保存）'), findsOneWidget);
        expect(find.text('2枚目（未保存）'), findsOneWidget);
        await tester.tap(find.text('写真を確定'));
        await tester.pumpAndSettle();
        expect(draft.map((p) => p.filename), ['front.jpg', 'back.jpg']);
        expect(identical(draft[0].bytes, first.bytes), isTrue);
        expect(identical(draft[1].bytes, second.bytes), isTrue);
      }
      expect(signedReads, 0);
    },
  );
}
