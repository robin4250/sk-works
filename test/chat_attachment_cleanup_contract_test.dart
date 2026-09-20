import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat attachment upload keeps metadata available for cleanup', () {
    final source =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    final metadataIndex = source.indexOf("from('chat_attachments').insert");
    final uploadIndex =
        source.indexOf('storage.from(_attachmentBucket).uploadBinary');
    final catchIndex = source.indexOf('} catch (_)', uploadIndex);
    final removeIndex =
        source.indexOf('storage.from(_attachmentBucket).remove', catchIndex);
    final deleteIndex =
        source.indexOf("from('chat_attachments').delete()", catchIndex);

    expect(metadataIndex, greaterThanOrEqualTo(0));
    expect(uploadIndex, greaterThan(metadataIndex));
    expect(catchIndex, greaterThan(uploadIndex));
    expect(removeIndex, greaterThan(catchIndex));
    expect(deleteIndex, greaterThan(removeIndex));
  });
}
