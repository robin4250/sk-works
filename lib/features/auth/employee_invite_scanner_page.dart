import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class EmployeeInviteCredentials {
  const EmployeeInviteCredentials({
    required this.phone,
    required this.password,
  });

  final String phone;
  final String password;
}

class EmployeeInviteScannerPage extends StatefulWidget {
  const EmployeeInviteScannerPage({super.key});

  @override
  State<EmployeeInviteScannerPage> createState() =>
      _EmployeeInviteScannerPageState();
}

class _EmployeeInviteScannerPageState extends State<EmployeeInviteScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded['type']?.toString() != 'sko_employee_invite') {
          throw const FormatException('not SKO invite');
        }
        final phone = decoded['phone']?.toString() ?? '';
        final password = decoded['password']?.toString() ?? '';
        if (phone.isEmpty || password.isEmpty) {
          throw const FormatException('missing credential');
        }

        _handled = true;
        Navigator.of(context).pop(
          EmployeeInviteCredentials(
            phone: phone,
            password: password,
          ),
        );
        return;
      } catch (_) {
        setState(() {
          _message = 'SKO従業員登録用のQRコードではありません。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('従業員登録QRを読み取る')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'SKOを利用している人が表示した従業員登録QRコードを'
                    '枠内に映してください。',
                    textAlign: TextAlign.center,
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
