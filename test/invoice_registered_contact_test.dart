import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_cloud_repository.dart';

void main() {
  test(
    'registered customer contact uses real fields and keeps missing fallback',
    () {
      final contact = InvoiceCloudRepository.registeredCustomerContact(
        {'name': ' 登録取引会社 ', 'address': '東京都登録住所', 'phone': '03-1234-5678'},
        fallback: {
          'name': '旧名称',
          'postal_code': '100-0001',
          'address': '旧住所',
          'phone': '',
        },
      );
      expect(contact, {
        'name': '登録取引会社',
        'postal_code': '100-0001',
        'address': '東京都登録住所',
        'phone': '03-1234-5678',
      });
      expect(
        InvoiceCloudRepository.registeredCustomerContact({})['phone'],
        isEmpty,
      );
    },
  );
}
