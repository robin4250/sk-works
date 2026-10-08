import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payment certificates are reachable from the management menu', () {
    final app = read('lib/app_v2.dart');
    expect(app, contains("key: 'payment_certificates'"));
    expect(app, contains("key: 'payment_certificate_settings'"));
    expect(app, contains('PaymentCertificatesPage'));
    expect(app, contains('PartnerPaymentSettingsPage'));
  });

  test('missing-setting notifications open the related settings pages', () {
    final page = read('lib/features/notifications/notifications_page.dart');
    expect(page, contains("'payroll_settings' =>"));
    expect(page, contains("'admin_sites' =>"));
    expect(page, contains("'payment_certificate_settings' =>"));
    expect(page, contains("'settings' =>"));
  });

  test('payment certificate settings explain zero-value draft behavior', () {
    final page =
        read('lib/features/payroll/payment_certificates_page.dart');
    expect(page, contains('未設定でも支払証明書は0円の下書きとして生成されます'));
    expect(page, contains('設定後は自動で再計算されます'));
  });
}
