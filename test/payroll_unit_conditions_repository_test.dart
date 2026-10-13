import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late PayrollUnitConditionsRepository repository;
  String? actor = 'actor-a';
  final bodies = <Map<String, dynamic>>[];
  Map<String, dynamic> response = {
    'version': 1,
    'month': '2026-10-01',
    'can_edit': true,
    'items': <dynamic>[],
  };
  Completer<void>? held;
  Completer<void>? received;
  setUp(() async {
    actor = 'actor-a';
    bodies.clear();
    held = null;
    received = null;
    response = {
      'version': 1,
      'month': '2026-10-01',
      'can_edit': true,
      'items': <dynamic>[],
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      bodies.add(
        Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        ),
      );
      received?.complete();
      if (held != null) await held!.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = PayrollUnitConditionsRepository.forTesting(
      client,
      () => actor,
    );
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });
  test('RPC saves stable ids, all units, month, version and explicit zero then reads saved data', () async {
    final current = await repository.load(
      'company-a',
      'worker-a',
      '2026-10-01',
    );
    final items = [
      for (final section in PayrollItemSection.values)
        for (final unit in PayrollItemUnit.values)
          PayrollUnitItemDraft(
            id: 'new-unit-item-${section.name}-${unit.name}',
            section: section,
            unit: unit,
            name: '${section.name} ${unit.name}',
            rate: '100',
            quantity: unit == PayrollItemUnit.hour ? '0' : '',
          ),
    ];
    response = {
      'version': 2,
      'month': '2026-10-01',
      'can_edit': true,
      'items': [
        for (final item in items)
          {
            'id': 'saved-${item.section.name}-${item.unit.name}',
            'section': item.section.name,
            'unit': item.unit.name,
            'name': item.name,
            'rate_yen': 100,
            'source': 'manual_hours',
            'quantity': item.unit == PayrollItemUnit.hour ? 0 : null,
          },
      ],
    };
    final saved = await repository.save(
      'company-a',
      'worker-a',
      current,
      items,
    );
    expect(bodies.last['p_expected_version'], 1);
    expect(bodies.last['p_month'], '2026-10-01');
    expect((bodies.last['p_items'] as List).length, 6);
    expect((bodies.last['p_items'] as List).first['id'], isNull);
    expect((bodies.last['p_items'] as List).first['quantity'], '0');
    expect(saved.version, 2);
    expect(saved.items.first.quantity, '0');
    expect(
      (await repository.load(
        'company-a',
        'worker-a',
        '2026-10-01',
      )).items.first.id,
      saved.items.first.id,
    );
  });
  test('late old actor response and a different month never replace current settings', () async {
    held = Completer<void>();
    received = Completer<void>();
    final pending = repository.load('company-a', 'worker-a', '2026-10-01');
    final check = expectLater(pending, throwsStateError);
    await received!.future;
    actor = 'actor-b';
    held!.complete();
    await check;
    held = null;
    received = null;
    response['month'] = '2026-09-01';
    await expectLater(
      repository.load('company-a', 'worker-a', '2026-10-01'),
      throwsStateError,
    );
  });
}
