import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_photos.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_selection.dart';

void main() {
  test('front back extras keep explicit draft order without changing saved objects', () {
    final front = WorkerDocumentPhoto.pending(
      Uint8List.fromList([1]),
      'front.jpg',
    );
    const back = WorkerDocumentPhoto.saved('back.jpg');
    const extra = WorkerDocumentPhoto.saved('extra.jpg');
    final selected = validateOwnQualificationPhotoSelection(
      photos: [front, back, extra],
      savedPaths: ['back.jpg', 'extra.jpg'],
    );
    expect(selected, [front, back, extra]);
    expect(() => selected.removeAt(0), throwsUnsupportedError);
    expect(
      validateOwnQualificationPhotoSelection(
        photos: [],
        savedPaths: ['back.jpg'],
      ),
      isEmpty,
    );
  });
  test('foreign saved path, duplicate retained path and empty new photo fail closed', () {
    for (final photos in [
      [const WorkerDocumentPhoto.saved('other.jpg')],
      [
        const WorkerDocumentPhoto.saved('own.jpg'),
        const WorkerDocumentPhoto.saved('own.jpg'),
      ],
      [WorkerDocumentPhoto.pending(Uint8List(0), 'empty.jpg')],
      [WorkerDocumentPhoto.pending(Uint8List(1), '')],
      List.generate(
        21,
        (i) => WorkerDocumentPhoto.pending(Uint8List(1), '$i.jpg'),
      ),
    ]) {
      expect(
        () => validateOwnQualificationPhotoSelection(
          photos: photos,
          savedPaths: ['own.jpg'],
        ),
        throwsStateError,
      );
    }
  });
}
