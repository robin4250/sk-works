import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleting own chat message removes attachment storage first', () {
    final source =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    final methodIndex = source.indexOf('Future<void> deleteOwnMessage');
    final attachmentReadIndex =
        source.indexOf("from('chat_attachments')", methodIndex);
    final storageRemoveIndex =
        source.indexOf('storage.from(_attachmentBucket).remove', methodIndex);
    final messageDeleteIndex =
        source.indexOf("from('chat_messages').delete()", methodIndex);

    expect(methodIndex, greaterThanOrEqualTo(0));
    expect(attachmentReadIndex, greaterThan(methodIndex));
    expect(storageRemoveIndex, greaterThan(attachmentReadIndex));
    expect(messageDeleteIndex, greaterThan(storageRemoveIndex));
  });
}
