import 'package:flutter_test/flutter_test.dart';

import '../lib/features/security/master_self_operation_audit.dart';

Map<String, Object> response({bool auth = false}) => {
  'version': 1,
  'source_provenance': auth
      ? 'supabase_auth_database_audit'
      : 'server_master_operation_audit',
  'scope': 'self_master_account',
  'limit': 100,
  'cutoff': '2026-10-14T03:00:00.000Z',
  'events': [
    {
      'action': auth ? 'login' : 'master_device_bootstrap',
      'at': '2026-10-14T01:00:00.000Z',
    },
  ],
};

void main() {
  test('separate trusted sources and labels, including empty actual audit', () {
    expect(
      MasterSelfOperationAuditEvent.parse(response()).single.label(false),
      '最初のマスター端末を登録',
    );
    expect(
      MasterSelfOperationAuditEvent.parse(
        response(auth: true),
        auth: true,
      ).single.label(false),
      'ログイン',
    );
    expect(
      MasterSelfOperationAuditEvent.parse({
        ...response(auth: true),
        'events': [],
      }, auth: true),
      isEmpty,
    );
    expect(
      () => MasterSelfOperationAuditEvent.parse(response(auth: true)),
      throwsFormatException,
    );
    expect(
      () => MasterSelfOperationAuditEvent.parse({
        ...response(),
        'source_provenance': 'synthetic_fixture',
      }),
      throwsFormatException,
    );
  });
  test('reject free text, extra identifiers, mixed source actions and invalid chronology', () {
    for (final event in [
      {'action': 'forbidden', 'at': '2026-10-14T01:00:00.000Z'},
      {
        'action': 'master_device_bootstrap',
        'at': '2026-10-14T01:00:00.000Z',
        'email': 'forbidden',
      },
      {'action': 'master_device_bootstrap', 'at': '2026-02-30T01:00:00.000Z'},
      {'action': 'login', 'at': '2026-10-14T01:00:00.000Z'},
    ]) {
      expect(
        () => MasterSelfOperationAuditEvent.parse({
          ...response(),
          'events': [event],
        }),
        throwsFormatException,
      );
    }
    expect(
      () => MasterSelfOperationAuditEvent.parse({
        ...response(),
        'events': [
          {
            'action': 'master_device_bootstrap',
            'at': '2026-10-14T01:00:00.000Z',
          },
          {
            'action': 'master_device_bootstrap',
            'at': '2026-10-14T02:00:00.000Z',
          },
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => MasterSelfOperationAuditEvent.parse({
        ...response(),
        'events': List.filled(101, {
          'action': 'master_device_bootstrap',
          'at': '2026-10-14T01:00:00.000Z',
        }),
      }),
      throwsFormatException,
    );
  });
}
