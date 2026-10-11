import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/own_qualification_photo_contract.dart';

void main() {
  final slots = <Map<String, dynamic>>[
    {'extension': 'jpg'},
    {'existing_path': 'legacy.pdf'},
  ];
  Map<String, dynamic> payload() => {
    'version': 1,
    'id': 'request',
    'target_id': 'target',
    'requested_by': 'user',
    'photo_paths': [
      'company/worker/target/submissions/request-1.jpg',
      'legacy.pdf',
    ],
    'upload_paths': [
      {
        'index': 0,
        'extension': 'jpg',
        'path': 'company/worker/target/submissions/request-1.jpg',
      },
    ],
    'status': 'draft',
    'cancelled': false,
  };
  OwnQualificationPreparedPhotos parse(Map<String, dynamic> raw) =>
      OwnQualificationPreparedPhotos.parse(
        raw,
        requestId: 'request',
        targetId: 'target',
        userId: 'user',
        companyId: 'company',
        workerId: 'worker',
        slots: slots,
      );
  test(
    'retains ordered PDF and limits uploads to exact generated object paths',
    () {
      final result = parse(payload());
      expect(result.paths.last, 'legacy.pdf');
      expect(result.uploads.keys, [0]);
      expect(() => result.paths.add('another'), throwsUnsupportedError);
      final cancelled = payload()
        ..['status'] = 'rejected'
        ..['cancelled'] = true;
      expect(parse(cancelled).cancelled, true);
    },
  );
  test(
    'mismatched owner, target, slots and cancellation states are rejected',
    () {
      for (final altered in [
        payload()..['requested_by'] = 'other',
        payload()..['target_id'] = 'other',
        payload()..['photo_paths'] = ['foreign.jpg', 'legacy.pdf'],
        payload()
          ..['photo_paths'] = [
            'company/worker/target/submissions/request-1.jpg',
          ],
        payload()..['cancelled'] = true,
        payload()..['cancelled'] = 'true',
        payload()..['upload_paths'] = [],
      ]) {
        expect(() => parse(altered), throwsStateError);
      }
    },
  );
}
