import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults stay in initial load and saved presence protects reopened payload', () {
    final source=File('lib/features/shared/trade_document_attachment_editor_page.dart').readAsStringSync();
    final load=source.substring(source.indexOf('Future<void> _load()'),source.indexOf('@override void dispose'));
    expect(load,contains('hasSavedAttachment: saved is Map'));
    expect(load,contains("if (saved is! Map && widget.subjectKind == 'invoice')"));
    expect(load.indexOf("_payload.remove('issue_date')"),lessThan(load.indexOf('r18InitialValues')));
    expect(load.indexOf('r18InitialValues'),lessThan(load.indexOf('widget.initialInput?.apply')));
    expect(load,contains("sourceDefaults: Map<String, dynamic>.from(data['defaults'] as Map)"));
    expect(load,isNot(contains('_repo!.save')));
    expect(load,isNot(contains('_repo.save')));
    final save=source.substring(source.indexOf('Future<void> _save()'),source.indexOf('@override Widget build'));
    expect(save,isNot(contains('r18InitialValues')));
    expect(source,contains('before the explicit save'));
  });
}
