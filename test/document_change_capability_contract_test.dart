import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/worker_document_change_repository.dart';
void main() {
  Map<String, dynamic> payload(int version, Object? upload) => {'version':version,'change_requests_available':true,'new_upload_available':upload,'max_photos':20,'self_approval_allowed':false};
  test('legacy v1 remains valid only with upload disabled', () {
    expect(WorkerDocumentChangeCapability.parse(payload(1,false)).available, isTrue);
    expect(WorkerDocumentChangeCapability.parse(payload(1,true)).available, isFalse);
  });
  test('v2 accepts an explicit boolean without enabling uploads in the client', () {
    expect(WorkerDocumentChangeCapability.parse(payload(2,false)).available, isTrue);
    expect(WorkerDocumentChangeCapability.parse(payload(2,true)).available, isTrue);
    expect(WorkerDocumentChangeCapability.parse(payload(2,null)).available, isFalse);
    expect(WorkerDocumentChangeCapability.parse(payload(3,true)).available, isFalse);
    final malformed=payload(2,true)..['self_approval_allowed']=true;
    expect(WorkerDocumentChangeCapability.parse(malformed).available, isFalse);
  });
}
