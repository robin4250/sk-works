import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('company rate page explains one source of truth',(){
  final s=File('lib/features/settings/company_rate_settings_page.dart').readAsStringSync();
  expect(s,contains('会社共通の初期値・手当設定'));
  expect(s,contains('社員ごとの給与は「個別給与設定」'));
  expect(s,contains('現場ごとの請求単価は「管理者用現場データ」'));
  expect(s,contains('同じ単価を複数画面へ入力する必要はありません'));
  expect(s,contains('会社共通の初期勤務単価（旧互換）'));
 });
}
