import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/document_photo_draft.dart';

void main() {
  test('front and back remain separate and ordered', () {
    final draft = DocumentPhotoDraft<String>();
    draft.add('front');
    draft.add('back');
    draft.addAll(['extra']);
    expect(draft.photos, ['front', 'back', 'extra']);
    expect(draft.removeAt(1), 'back');
    expect(draft.photos, ['front', 'extra']);
  });

  test('external callers cannot mutate the photo list', () {
    final draft = DocumentPhotoDraft<String>(['front']);
    expect(() => draft.photos.add('back'), throwsUnsupportedError);
    expect(draft.photos, ['front']);
  });
}
