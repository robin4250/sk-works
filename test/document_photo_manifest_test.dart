import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/document_photo_manifest.dart';

void main() {
  const front = DocumentPhotoEntry(
    path: 'company/document/front.jpg',
    contentType: 'image/jpeg',
  );
  const back = DocumentPhotoEntry(
    path: 'company/document/back.png',
    contentType: 'image/png',
  );

  test('keeps front and back in order', () {
    final entries = DocumentPhotoManifest.validate(
      companyId: 'company',
      documentId: 'document',
      entries: [front, back],
    );
    expect(entries.map((e) => e.path), [
      'company/document/front.jpg',
      'company/document/back.png',
    ]);
    expect(() => entries.add(front), throwsUnsupportedError);
  });

  test('rejects cross-company paths', () {
    expect(
      () => DocumentPhotoManifest.validate(
        companyId: 'company',
        documentId: 'document',
        entries: [
          const DocumentPhotoEntry(
            path: 'other/document/front.jpg',
            contentType: 'image/jpeg',
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('round trip validates saved photo order', () {
    final saved = [front.toJson(), back.toJson()];
    final restored = DocumentPhotoManifest.decode(
      companyId: 'company',
      documentId: 'document',
      value: saved,
    );
    expect(restored.map((e) => e.path), [front.path, back.path]);
  });

  test('rejects malformed saved photo metadata', () {
    expect(
      () => DocumentPhotoManifest.decode(
        companyId: 'company',
        documentId: 'document',
        value: [{'path': 'company/document/front.jpg'}],
      ),
      throwsStateError,
    );
  });

  test('rejects duplicate photos', () {
    expect(
      () => DocumentPhotoManifest.validate(
        companyId: 'company',
        documentId: 'document',
        entries: [front, front],
      ),
      throwsStateError,
    );
  });
}
