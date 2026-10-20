import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_uploaded_seal_png.dart';

void main() {
  const png = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
  test('valid alpha PNG is copied and content hash remains stable', () {
    final input = base64Decode(png);
    final image = CompanyUploadedSealPng.fromBytes(input);
    expect(image.width, 32); expect(image.height, 32);
    expect(image.sha256, '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc');
    input[0] = 0;
    expect(image.base64, png);
    expect(() => image.bytes[0] = 0, throwsUnsupportedError);
  });
  test('invalid image, truncated data, corrupt CRC, excessive bytes and hash mismatch fail', () {
    expect(() => CompanyUploadedSealPng.fromBytes(Uint8List(70)), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBytes(base64Decode(png).sublist(0, 70)), throwsFormatException);
    final corrupt = base64Decode(png);
    corrupt[50] ^= 1;
    expect(() => CompanyUploadedSealPng.fromBytes(corrupt), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBytes(Uint8List(CompanyUploadedSealPng.maxBytes + 1)), throwsFormatException);
    expect(() => CompanyUploadedSealPng.fromBase64(png, expectedSha256: 'wrong'), throwsFormatException);
  });
}
