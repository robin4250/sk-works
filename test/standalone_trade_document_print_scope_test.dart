import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/standalone_trade_document_print_scope.dart';

class Fixture {
  Uint8List? bytes = Uint8List.fromList([1, 2, 3]);
  String target = 'company:order';
  bool valid = true;
  int revocations = 0;
  late final scope = StandaloneTradeDocumentPrintScope(
    verifyScope: () {
      if (!valid) { throw StateError('token changed'); }
    },
    currentBytes: () => bytes,
    currentTarget: () => target,
    onRevoke: () { revocations++; },
  );
}
void main() {
  test('explicit print permits inactive layout only with the exact bytes', () {
    final f = Fixture();
    f.scope.begin(f.bytes!);
    f.scope.visibilityChanged(StandalonePrintVisibility.inactive);
    expect(identical(f.scope.layout(), f.bytes), isTrue);
    expect(f.revocations, 0);
    f.scope.visibilityChanged(StandalonePrintVisibility.resumed);
    f.scope.end();
    expect(f.revocations, 0);
    expect(() => f.scope.layout(), throwsStateError);
  });
  test('normal inactive invalidates and resume does not restore it', () {
    final f = Fixture();
    f.scope.visibilityChanged(StandalonePrintVisibility.inactive);
    f.scope.visibilityChanged(StandalonePrintVisibility.resumed);
    expect(() => f.scope.begin(f.bytes!), throwsStateError);
    expect(f.revocations, 1);
  });
  for (final state in [StandalonePrintVisibility.hidden,
      StandalonePrintVisibility.paused, StandalonePrintVisibility.detached]) {
    test('print does not exempt $state', () {
      final f = Fixture();
      f.scope.begin(f.bytes!);
      f.scope.visibilityChanged(state);
      expect(() => f.scope.layout(), throwsStateError);
      expect(f.revocations, 1);
    });
  }
  test('scope validator rejects token change during inactive print', () {
    final f = Fixture();
    f.scope.begin(f.bytes!);
    f.scope.visibilityChanged(StandalonePrintVisibility.inactive);
    f.valid = false;
    expect(() => f.scope.layout(), throwsStateError);
    expect(f.revocations, 1);
  });
  test('equal content in a different bytes object does not inherit print lease', () {
    final f = Fixture();
    f.scope.begin(f.bytes!);
    f.bytes = Uint8List.fromList([1, 2, 3]);
    expect(() => f.scope.layout(), throwsStateError);
  });
  test('target change cannot inherit print lease', () {
    final f = Fixture();
    f.scope.begin(f.bytes!);
    f.target = 'other-company:order';
    expect(() => f.scope.layout(), throwsStateError);
  });
  test('print end while inactive returns to normal invalidation', () {
    final f = Fixture();
    f.scope.begin(f.bytes!);
    f.scope.visibilityChanged(StandalonePrintVisibility.inactive);
    f.scope.end();
    expect(f.revocations, 1);
    expect(() => f.scope.layout(), throwsStateError);
  });
}
