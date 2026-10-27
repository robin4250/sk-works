import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_bell.dart';

void main() {
  test('失敗は0件と区別し回復後に解除', () async {
    final state = NotificationBadgeRefresh();
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => throw StateError('pending unavailable'));
    expect(state.count, 0);
    expect(state.uncertain, isTrue);
    await state.refresh(currentActor: () => 'a', loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.count, 0);
    expect(state.uncertain, isFalse);
    await state.refresh(currentActor: () => 'a',
      loadUnread: () async => throw StateError('unread unavailable'),
      loadPending: () async => []);
    expect(state.uncertain, isTrue);
  });

  test('古いアカウントの失敗を新アカウントへ引き継がない', () async {
    final state = NotificationBadgeRefresh();
    final pending = Completer<void>();
    var actor = 'a';
    final first = state.refresh(currentActor: () => actor,
      loadUnread: () async { await pending.future; throw StateError('old'); },
      loadPending: () async => []);
    actor = 'b';
    pending.complete();
    await first;
    await state.refresh(currentActor: () => actor, loadUnread: () async => [],
      loadPending: () async => []);
    expect(state.uncertain, isFalse);
    expect(state.count, 0);
  });

  test('取得中に切替えた新しい本人の結果は古い失敗で消えない', () async {
    final state = NotificationBadgeRefresh();
    final firstPending = Completer<void>();
    var actor = 'a';
    final first = state.refresh(currentActor: () => actor,
      loadUnread: () async { await firstPending.future; throw StateError('old'); },
      loadPending: () async => []);
    actor = 'b';
    await state.refresh(currentActor: () => actor, loadUnread: () async => [],
      loadPending: () async => throw StateError('new'));
    expect(state.uncertain, isTrue);
    firstPending.complete();
    await first;
    expect(state.uncertain, isTrue);
  });
}
