import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notes/notes_cloud_page.dart';

void main() {
  test('old group response cannot replace a newer group', () {
    final guard = CommunicationLoadGuard();
    final old = guard.invalidate();
    final current = guard.invalidate();
    expect(guard.accepts(old, 'a', 'a', requestedGroup: 'g1', currentGroup: 'g2'), isFalse);
    expect(guard.accepts(current, 'a', 'a', requestedGroup: 'g2', currentGroup: 'g2'), isTrue);
  });
  test('logout and account switch reject previous actor data', () {
    final guard = CommunicationLoadGuard();
    final ticket = guard.invalidate();
    expect(guard.accepts(ticket, 'a', null), isFalse);
    expect(guard.accepts(ticket, 'a', 'b'), isFalse);
    expect(guard.accepts(ticket, null, null), isFalse);
  });
  test('permission reload invalidates pending content even for same actor', () {
    final guard = CommunicationLoadGuard();
    final ticket = guard.invalidate();
    guard.invalidate();
    expect(guard.accepts(ticket, 'a', 'a', requestedGroup: 'g', currentGroup: 'g'), isFalse);
  });
}
