import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ExpenseReceiptAttachment {
  const ExpenseReceiptAttachment(this.localPath, this.sha256Hex, this.size, this.mime);
  final String localPath, sha256Hex, mime;
  final int size;
  static String _mime(Uint8List bytes) {
    if (bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) return 'image/jpeg';
    if (bytes.length > 8 && bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') return 'image/png';
    throw StateError('領収書はJPEGまたはPNGの写真を選択してください。');
  }
  static Future<ExpenseReceiptAttachment> capture(XFile selected) async {
    final bytes = await selected.readAsBytes();
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) throw StateError('領収書の写真は10MB以内にしてください。');
    final mime = _mime(bytes), digest = sha256.convert(bytes).toString();
    final root = await getApplicationSupportDirectory();
    final directory = await Directory('${root.path}/expense_receipts').create(recursive: true);
    final path = '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$digest.${mime == 'image/png' ? 'png' : 'jpg'}';
    await File(path).writeAsBytes(bytes, flush: true);
    return ExpenseReceiptAttachment(path, digest, bytes.length, mime);
  }
  Future<Uint8List> verifiedBytes() async {
    final bytes = await File(localPath).readAsBytes();
    if (bytes.length != size || sha256.convert(bytes).toString() != sha256Hex || _mime(bytes) != mime) {
      throw StateError('再送用の領収書が一致しません。保存済み申請を確認してください。');
    }
    return bytes;
  }
  Map<String, dynamic> get encoded => {'local_path': localPath, 'sha256': sha256Hex, 'size': size, 'mime': mime};
  factory ExpenseReceiptAttachment.decode(Map<String, dynamic> value) {
    if (value['local_path'] is! String || (value['local_path'] as String).isEmpty ||
        value['sha256'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256']) ||
        value['size'] is! int || value['size'] < 1 || value['size'] > 10 * 1024 * 1024 ||
        !['image/jpeg','image/png'].contains(value['mime'])) {
      throw StateError('保留領収書を確認できません。');
    }
    return ExpenseReceiptAttachment(value['local_path'], value['sha256'], value['size'], value['mime']);
  }
  String objectPath(String company, String actor, String claim) => '$company/$actor/$claim.${mime == 'image/png' ? 'png' : 'jpg'}';
}
