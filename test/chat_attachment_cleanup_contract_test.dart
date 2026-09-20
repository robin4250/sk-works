import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat attachment failures attempt both metadata and storage cleanup', () {
    final source =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    final insertIndex = source.indexOf("from('chat_attachments').insert");
    final catchIndex = source.indexOf('} catch (_)', insertIndex);
    final deleteIndex =
        source.indexOf("from('chat_attachments').delete()", catchIndex);
    final removeIndex =
        source.indexOf('storage.from(_attachmentBucket).remove', catchIndex);

    expect(insertIndex, greaterThanOrEqualTo(0));
    expect(catchIndex, greaterThan(insertIndex));
    expect(deleteIndex, greaterThan(catchIndex));
    expect(removeIndex, greaterThan(deleteIndex));
  });
}
