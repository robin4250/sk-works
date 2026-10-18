import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_change_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const company = '10000000-0000-0000-0000-000000000003';
const worker = '10000000-0000-0000-0000-000000000004';
const requirement = '10000000-0000-0000-0000-000000000005';
const target = '10000000-0000-0000-0000-000000000006';
const request = '10000000-0000-0000-0000-000000000007';
WorkerDocumentChangeCommand command() => WorkerDocumentChangeCommand(
  requestId: request,
  targetId: target,
  companyId: company,
  workerId: worker,
  requirementId: requirement,
  requestedBy: actor,
  expectedUpdatedAt: '2026-10-19T00:00:00Z',
  paths: ['retained/front.jpg'],
  expiresAt: '2027-10-19',
  notes: 'Updated note',
);
Map<String, dynamic> receipt({String status = 'draft'}) => {
  'version': 1,
  'id': request,
  'target_id': target,
  'company_id': company,
  'worker_id': worker,
  'requirement_id': requirement,
  'requested_by': actor,
  'status': status,
  'can_review': false,
  'previous': {
    'id': target,
    'company_id': company,
    'worker_id': worker,
    'requirement_id': requirement,
    'updated_at': '2026-10-19T00:00:00+00:00',
  },
  'proposed': command().proposed,
};
Map<String, dynamic> capability() => {
  'version': 1,
  'change_requests_available': true,
  'new_upload_available': false,
  'max_photos': 20,
  'self_approval_allowed': false,
};

class Fixture {
  String? current = actor;
  final changes = StreamController<void>.broadcast(sync: true);
  final calls = <({String action, Map<String, dynamic> data})>[];
  Future<Object?> Function(String, Map<String, dynamic>)? response;
  late final repo = WorkerDocumentChangeRepository.forTesting(
    actor: () => current,
    changes: changes.stream,
    rpc: (action, data) {
      calls.add((action: action, data: data));
      return response == null
          ? Future.value(receipt())
          : response!(action, data);
    },
  );
  void change(String? user) {
    current = user;
    changes.add(null);
  }

  Future<void> dispose() async {
    await repo.dispose();
    await changes.close();
  }
}

void main() {
  test(
    'actual SDK uses only the candidate RPC and fixed prepare payload',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://document-change-fixture.invalid',
        'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          requests.add(r);
          final payload = jsonDecode(r.body) as Map;
          return http.Response(
            jsonEncode(
              payload['p_action'] == 'capability' ? capability() : receipt(),
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'synthetic-token',
          'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'user': {
            'id': actor,
            'aud': 'authenticated',
            'role': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-10-19T00:00:00Z',
          },
        }),
      );
      final repo = WorkerDocumentChangeRepository(client);
      try {
        expect((await repo.capability()).available, isTrue);
        expect((await repo.prepare(command())).status, 'draft');
        expect(requests.length, 2);
        for (final r in requests) {
          expect(r.url.path, '/rest/v1/rpc/worker_document_change');
          expect(r.method, 'POST');
        }
        expect(jsonDecode(requests.last.body), {
          'p_action': 'prepare',
          'p_data': command().preparePayload,
        });
      } finally {
        await repo.dispose();
        await client.dispose();
      }
    },
  );

  test('invalid command identities, dates and repeated photos are refused', () {
    for (final field in ['id', 'timestamp', 'date', 'paths']) {
      expect(
        () => WorkerDocumentChangeCommand(
          requestId: field == 'id' ? ' $request' : request,
          targetId: target,
          companyId: company,
          workerId: worker,
          requirementId: requirement,
          requestedBy: actor,
          expectedUpdatedAt: field == 'timestamp'
              ? '2026-10-19'
              : '2026-10-19T00:00:00Z',
          paths: field == 'paths' ? ['a.jpg', 'a.jpg'] : ['a.jpg'],
          expiresAt: field == 'date' ? '2027-02-30' : null,
          notes: null,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'capability refuses malformed, upload enabled or self approval contracts',
    () {
      expect(
        WorkerDocumentChangeCapability.parse(capability()).available,
        isTrue,
      );
      for (final value in [
        null,
        {},
        {...capability(), 'new_upload_available': true},
        {...capability(), 'self_approval_allowed': true},
        {...capability(), 'max_photos': 20.0},
        {...capability(), 'extra': true},
      ]) {
        expect(WorkerDocumentChangeCapability.parse(value).available, isFalse);
      }
    },
  );
  test(
    'fixed command is immutable and prepare never contains company override or uploads',
    () async {
      final f = Fixture();
      try {
        final c = command();
        expect(() => c.paths.add('another'), throwsUnsupportedError);
        expect((await f.repo.prepare(c)).status, 'draft');
        expect(f.calls.single.action, 'prepare');
        expect(f.calls.single.data, {
          'request_id': request,
          'status_id': target,
          'expected_updated_at': '2026-10-19T00:00:00Z',
          'proposed': c.proposed,
        });
      } finally {
        await f.dispose();
      }
    },
  );
  for (final key in [
    'id',
    'target_id',
    'company_id',
    'worker_id',
    'requirement_id',
    'requested_by',
    'status',
  ]) {
    test('wrong response $key fails closed', () async {
      final f = Fixture()
        ..response = (_, __) async => {...receipt(), key: other};
      try {
        await expectLater(f.repo.prepare(command()), throwsFormatException);
      } finally {
        await f.dispose();
      }
    });
  }
  test('changed previous timestamp or proposed content is not accepted', () {
    for (final row in [
      {
        ...receipt(),
        'previous': {
          ...receipt()['previous'] as Map,
          'updated_at': '2026-10-20T00:00:00Z',
        },
      },
      {
        ...receipt(),
        'proposed': {...command().proposed, 'notes': 'Different'},
      },
      {
        ...receipt(),
        'proposed': {
          ...command().proposed,
          'attachment_paths': ['other.jpg'],
        },
      },
    ]) {
      expect(
        () => WorkerDocumentChangeReceipt.parse(row, command()),
        throwsFormatException,
      );
    }
  });
  test('missing API is unavailable without fallback writes', () async {
    final f = Fixture()
      ..response = (_, __) async =>
          throw const PostgrestException(message: 'missing', code: 'PGRST202');
    try {
      expect((await f.repo.capability()).available, isFalse);
      expect(f.calls.map((c) => c.action), ['capability']);
      await expectLater(
        f.repo.prepare(command()),
        throwsA(isA<PostgrestException>()),
      );
      expect(f.calls.map((c) => c.action), ['capability', 'prepare']);
    } finally {
      await f.dispose();
    }
  });
  for (final failure in [false, true]) {
    test(
      'ABA actor invalidates late response and any future operation, failure=$failure',
      () async {
        final done = Completer<Object?>();
        final f = Fixture()..response = (_, __) => done.future;
        try {
          final pending = f.repo.prepare(command());
          final expectation = expectLater(pending, throwsStateError);
          f.change(other);
          f.change(actor);
          if (failure) {
            done.completeError(StateError('transport'));
          } else {
            done.complete(receipt());
          }
          await expectation;
          await expectLater(f.repo.detail(command()), throwsStateError);
          expect(f.calls.length, 1);
        } finally {
          await f.dispose();
        }
      },
    );
  }
  test(
    'same request pending result is accepted; detail is read only',
    () async {
      final f = Fixture()
        ..response = (_, __) async => receipt(status: 'pending');
      try {
        expect((await f.repo.submit(command())).status, 'pending');
        expect((await f.repo.detail(command())).status, 'pending');
        expect(f.calls.map((c) => c.action), ['submit', 'detail']);
        expect(f.calls.every((c) => c.data['request_id'] == request), isTrue);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'double command is refused and unknown result does not retry automatically',
    () async {
      final done = Completer<Object?>();
      final f = Fixture()..response = (_, __) => done.future;
      try {
        final first = f.repo.submit(command());
        await expectLater(f.repo.submit(command()), throwsStateError);
        final expectation = expectLater(first, throwsStateError);
        done.completeError(StateError('unknown outcome'));
        await expectation;
        expect(f.calls.length, 1);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'self review is refused before RPC, reviewer result must match chosen operation',
    () async {
      final f = Fixture();
      try {
        expect(() => f.repo.review(command(), approve: true), throwsStateError);
        expect(f.calls, isEmpty);
      } finally {
        await f.dispose();
      }
      final reviewer = Fixture()..current = other;
      reviewer.response = (_, __) async => receipt(status: 'pending');
      try {
        expect(
          () => reviewer.repo.review(command(), approve: false, reason: ' '),
          throwsStateError,
        );
        await expectLater(
          reviewer.repo.review(command(), approve: true),
          throwsFormatException,
        );
        reviewer.response = (_, __) async => receipt(status: 'approved');
        expect(
          (await reviewer.repo.review(command(), approve: true)).status,
          'approved',
        );
      } finally {
        await reviewer.dispose();
      }
    },
  );
  test('dispose and auth stream error invalidate repository', () async {
    final f = Fixture();
    f.repo;
    f.changes.addError(StateError('auth stream'));
    await expectLater(f.repo.detail(command()), throwsStateError);
    expect(f.calls, isEmpty);
    await f.dispose();
    await expectLater(f.repo.prepare(command()), throwsStateError);
  });
}
