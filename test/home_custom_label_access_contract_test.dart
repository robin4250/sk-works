import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home labels can be preconfigured with explicit two-line breaks', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains('sko_home_label_override_'));
    expect(app, contains("labelText: '1行目'"));
    expect(app, contains("labelText: '2行目（不要なら空欄）'"));
    expect(app, contains("].join('\\n')"));
    expect(app, contains("tooltip: '2行表示時の改行位置'"));
    expect(home, contains('final needsTwoLines = painter.width > constraints.maxWidth'));
    expect(home, contains('maxLines: needsTwoLines ? 2 : 1'));
    expect(app, contains('1行で収まる時は1行表示のままです'));
  });

  test('home access borders follow the restored four-level rule', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(home, contains('HomeShortcutAccess.general'));
    expect(home, contains('HomeShortcutAccess.subAdmin'));
    expect(home, contains('HomeShortcutAccess.viewer'));
    expect(home, contains('HomeShortcutAccess.admin'));
    expect(home, contains('isAdmin ? 4.0'));
    expect(home, contains('isSubAdmin || isViewer ? 1.8 : 0.0'));
    expect(home, contains('if (isViewer)'));
    expect(home, isNot(contains('_ProfessionalAccessMark')));
  });

  test('home opacity changes persist immediately and reload after closing', () {
    final appearance =
        File('lib/features/home/home_appearance.dart').readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(appearance, contains('Future<void> _persistCurrent()'));
    expect(appearance, contains('onChangeEnd: (_) => _persistCurrent()'));
    expect(appearance, contains("'ヘッダー透明度プレビュー'"));
    expect(appearance, contains('Colors.white.withValues(alpha: opacity)'));
    expect(app, contains('value ?? await HomeAppearanceRepository.load()'));
  });
}
