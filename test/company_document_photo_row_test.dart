import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/company_document_photo_row.dart';

void main() {
  testWidgets(
    'photo removal stays visible in a narrow dialog with larger text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var removed = 0, previewed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: Scaffold(
                body: AlertDialog(
                  scrollable: true,
                  title: const Text('書類の写真'),
                  content: SizedBox(
                    width: 340,
                    child: CompanyDocumentPhotoRow(
                      label: '追加写真 1',
                      subtitle: '登録済み',
                      onPreview: () => previewed++,
                      onRemove: () => removed++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('写真を削除'));
      expect(removed, 1);
      expect(previewed, 0);
    await tester.tap(find.text('プレビュー'));
    expect(previewed, 1);
      await tester.tap(find.text('追加写真 1'));
    expect(previewed, 2);
    },
  );
}
