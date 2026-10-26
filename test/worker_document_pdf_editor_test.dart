import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photo_editor.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';

void main() {
  testWidgets('PDF and gallery are available and a pending PDF is not decoded as an image', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => editWorkerDocumentPhotos(context, paths: const [], signedUrl: (_) async => '', initialPhotos: [WorkerDocumentPhoto.pending(Uint8List.fromList('%PDF-test'.codeUnits), 'fixture.pdf')]),
      child: const Text('開く'),
    )))));
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('PDF書類'), findsOneWidget);
    expect(find.text('PDFを選択'), findsOneWidget);
    expect(find.text('複数選択'), findsOneWidget);
    expect(find.text('1枚撮影'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
  });
}
