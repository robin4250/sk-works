import 'dart:io';
import 'package:sk_works/features/payroll/payment_order_layout.dart';

// Dependency-free regression check. No Flutter startup, network or user data.
void main() {
  final shortOrder = <String, dynamic>{
    'work_name': '内装工事',
    'work_address': '東京都',
    'issuer': {'name': '発注会社'},
    'counterparty': {'name': '受注会社'},
    'notes': '合意した工事',
  };
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  check(
    !paymentOrderUsesCompactLayout(shortOrder),
    'short text must stay normal',
  );
  final uploaded = {
    ...shortOrder,
    'company_seal_snapshot': {
      'style': 'uploaded',
      'uploaded_png': 'A' * 100000,
    },
  };
  check(
    uploaded.toString().length > 1800,
    'reproduce previous image-length bug',
  );
  check(!paymentOrderUsesCompactLayout(uploaded), 'image must not shrink text');
  check(
    !paymentOrderUsesCompactLayout({...uploaded, 'internal': 'X' * 100000}),
    'hidden metadata must not shrink text',
  );
  final longOrder = {...shortOrder, 'notes': '特記事項' * 500};
  check(
    paymentOrderUsesCompactLayout(longOrder),
    'long visible text must fit compactly',
  );
  check(
    paymentOrderUsesCompactLayout({
      ...longOrder,
      'company_seal_snapshot': uploaded['company_seal_snapshot'],
    }),
    'long visible text must stay compact with an uploaded seal',
  );
  check(!paymentOrderUsesCompactLayout({'notes': 'X' * 1800}), '1800 boundary');
  check(paymentOrderUsesCompactLayout({'notes': 'X' * 1801}), '1801 boundary');
  stdout.writeln(
    'PASS 7 order layout checks: visible text, uploaded seal, metadata, boundary',
  );
}
