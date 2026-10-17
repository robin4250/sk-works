import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_device_management_page.dart';
import 'package:sk_works/features/settings/master_device_repository.dart';

MasterDeviceRecord device(String id, {bool locked = false, bool revoked = false}) => MasterDeviceRecord(
  id: id, deviceName: 'synthetic $id', deviceType: 'iphone', registeredAt: DateTime(2026),
  isLocked: locked, revokedAt: revoked ? DateTime(2026) : null);
class Devices implements MasterDeviceRepository {
  Devices(this.rows);
  final List<MasterDeviceRecord> rows;
  int writes = 0;
  @override String? get currentUserId => 'synthetic-master';
  @override Future<bool> isMasterAdmin({String? accessToken}) async => true;
  @override Future<List<MasterDeviceRecord>> loadDevices() async => rows;
  @override Future<bool> lockReauthenticationRequired() async => false;
  @override Future<void> setLocked({required String deviceId, required bool locked, String? proof}) async { writes++; }
  @override Future<void> revoke(String deviceId) async { writes++; }
  @override dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected fixture call');
}
void main() {
  test('locked/revoked backup is not a usable alternative', () {
    final a = device('a');
    expect(removesLastUsableMasterDevice([a], a), true);
    expect(removesLastUsableMasterDevice([a, device('b', locked:true)], a), true);
    expect(removesLastUsableMasterDevice([a, device('b', revoked:true)], a), true);
    expect(removesLastUsableMasterDevice([a, device('b')], a), false);
    expect(removesLastUsableMasterDevice([device('a', locked:true)], device('a', locked:true)), false);
  });
  for (final label in ['ロック', '登録解除']) {
    testWidgets('last usable $label never sends mutation', (tester) async {
      final repo = Devices([device('a')]);
      await tester.pumpWidget(MaterialApp(home: MasterDeviceManagementPage(repository:repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton,label));await tester.pumpAndSettle();
      expect(find.text('最後の信頼済み端末は停止できません'), findsOneWidget);
      expect(repo.writes,0);
    });
  }
  testWidgets('lock is never a one-tap operation; cancel leaves state untouched', (tester) async {
    final repo=Devices([device('a'),device('b')]);
    await tester.pumpWidget(MaterialApp(home:MasterDeviceManagementPage(repository:repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton,'ロック').first);await tester.pumpAndSettle();
    expect(find.text('端末をロックしますか？'),findsOneWidget);expect(repo.writes,0);
    await tester.tap(find.text('戻る'));await tester.pumpAndSettle();expect(repo.writes,0);
  });
}
