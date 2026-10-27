import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/notification_target_policy.dart';

void main() {
  const id = '00000000-0000-0000-0000-000000000001';
  final row = {'id': id, 'status':'pending', 'can_review':true,
    'photo_contract_version':1, 'qualification_name':'合成資格'};
  test('only server-authorized pending photo requests become actionable', () {
    expect(mapQualificationPhotoAttention([row]).single.actionId, id);
    for (final altered in [
      {...row, 'can_review':false}, {...row, 'can_review':'true'},
      {...row, 'status':'approved'}, {...row, 'id':'invalid'},
      {...row, 'photo_contract_version':null},
    ]) {
      expect(mapQualificationPhotoAttention([altered]), isEmpty);
    }
    expect(() => mapQualificationPhotoAttention(null), throwsStateError);
  });
  test('distinct pending requests remain visible and repeated reads deduplicate by ID', () {
    final items = mapQualificationPhotoAttention([row,row,{...row,'id':'00000000-0000-0000-0000-000000000002'}]);
    expect(AttentionCenterSnapshot(items,now:DateTime(2026)).unresolvedCount,2);
    expect(notificationTargetIsValid('qualification_photo_request',null),false);
    expect(notificationTargetIsValid('qualification_photo_request',id),true);
  });
}
