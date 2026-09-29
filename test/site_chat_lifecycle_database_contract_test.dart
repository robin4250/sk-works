import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260930070000_connect_site_chat_lifecycle.sql',
    ).readAsStringSync();
  });

  test('site registration owns exactly one participant-only site chat', () {
    expect(sql, contains('one_site_chat_per_site'));
    expect(sql, contains('private.ensure_site_chat'));
    expect(sql, contains("group_type='site'"));
    expect(sql, contains('participants_only=true'));
    expect(sql, contains('sync_site_chat_lifecycle'));
  });

  test('attendance and clock-in join linked worker user to site chat', () {
    expect(sql, contains('attendance_join_site_chat'));
    expect(sql, contains('verification_join_site_chat'));
    expect(sql, contains('private.join_site_chat_for_worker'));
    expect(sql, contains("new.event_type='clock_in'"));
    expect(sql, contains('on conflict (group_id,user_id) do nothing'));
  });

  test('site chat access is participant-only except operational managers', () {
    expect(
      sql,
      contains("v_group_type='site'\n     and v_role in ('owner','admin','manager')"),
    );
    expect(sql, contains("v_group_type='direct' or v_participants_only"));
  });

  test('completed sites archive chat and archived chat cannot send', () {
    expect(sql, contains('archived_at timestamptz'));
    expect(sql, contains("when s.status='completed' then"));
    expect(sql, contains('g.id=p_group and g.archived_at is null'));
  });

  test('migration backfills existing sites and attendance membership', () {
    expect(sql, contains('from public.sites s'));
    expect(sql, contains('from public.attendance_entries ae'));
    expect(sql, contains('from public.attendance_verifications av'));
  });

  test('internal lifecycle helpers are not directly executable by clients', () {
    expect(
      sql,
      contains(
        'revoke all on function private.ensure_site_chat(uuid) from public,anon,authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on function private.join_site_chat_for_worker(uuid,uuid) from public,anon,authenticated',
      ),
    );
  });
}
