import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('owners and admins can save employee personnel directly', () {
    final migration = read(
      'supabase/migrations/'
      '20261006230434_allow_admin_direct_worker_personnel_save.sql',
    );

    expect(migration, contains("v_actor_role in ('owner','admin')"));
    expect(migration, contains("'saved_directly',true"));
    expect(migration, contains("'requires_approval',false"));
    expect(migration, contains('private.apply_worker_personnel_payload'));
  });

  test('manager path still keeps one-to-three approver workflow', () {
    final migration = read(
      'supabase/migrations/'
      '20261006230434_allow_admin_direct_worker_personnel_save.sql',
    );

    expect(migration, contains('worker_personnel_approvers'));
    expect(migration, contains('v_required:=least(v_required,3)'));
    expect(migration, contains('申請者本人は承認できません'));
    expect(migration, contains("'requires_approval',true"));
  });

  test('admin edit UI says save instead of approval request', () {
    final page = read(
      'lib/features/people/employee_personnel_edit_page.dart',
    );

    expect(page, contains("member.role == 'owner' || member.role == 'admin'"));
    expect(page, contains("'管理者は社員個人情報を直接登録・保存できます。承認者の設定は不要です。'"));
    expect(page, contains("_directAdminSave ? '保存する' : '変更申請を送る'"));
    expect(page, contains('Icons.save_outlined'));
  });
}
