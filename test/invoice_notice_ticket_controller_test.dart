import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_notice_ticket_controller.dart';

void main() {
  const notice = '00000000-0000-0000-0000-000000000001';
  const ticket = '00000000-0000-0000-0000-000000000002';
  const invoice = '00000000-0000-0000-0000-000000000003';
  final start = DateTime.utc(2026, 10, 27, 12);
  test('reopening a read notification obtains a fresh memory-only ticket', () async {
    var current = start, calls = 0;
    final c = InvoiceNoticeTicketController(actor: () => 'actor', session: () => 'session', now: () => current,
      openTicket: (_) async {calls++; return {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket, 'expires_at': current.add(const Duration(minutes: 5)).toIso8601String()};});
    expect(await c.open(notice, invoiceId: invoice), isTrue); expect(c.hasValidTicket, isTrue);
    current = current.add(const Duration(minutes: 5)); expect(c.hasValidTicket, isFalse);
    expect(await c.open(notice, invoiceId: invoice), isTrue); expect(c.hasValidTicket, isTrue); expect(calls, 2);
    c.invalidate(); expect(c.hasValidTicket, isFalse);
  });
  test('bad responses, unauthenticated state and network errors fail closed', () async {
    for (final result in [null, {}, {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket, 'expires_at': start.subtract(const Duration(seconds: 1)).toIso8601String()}, {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket, 'expires_at': start.add(const Duration(days: 1)).toIso8601String()}]) {
      final c = InvoiceNoticeTicketController(actor: () => 'actor', session: () => 'session', now: () => start, openTicket: (_) async => result);
      expect(await c.open(notice, invoiceId: invoice), isFalse); expect(c.hasValidTicket, isFalse);
    }
    final c = InvoiceNoticeTicketController(actor: () => null, session: () => 'session', openTicket: (_) async => throw StateError('offline'));
    expect(await c.open(notice, invoiceId: invoice), isFalse); expect(await c.open('bad-id', invoiceId: invoice), isFalse);
  });
  test('mismatched server receipt never enables the ticket', () async {
    final c = InvoiceNoticeTicketController(actor: () => 'a', session: () => 's', now: () => start,
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': notice, 'ticket_id': ticket,
        'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()});
    expect(await c.open(notice, invoiceId: invoice), isFalse);
    expect(c.hasValidTicket, isFalse);
  });
  test('account, session, and lifecycle change discard in-flight and saved tickets', () async {
    var actor = 'a', session = 's';
    final pending = Completer<Object?>();
    final c = InvoiceNoticeTicketController(actor: () => actor, session: () => session, now: () => start, openTicket: (_) => pending.future);
    final wait = c.open(notice, invoiceId: invoice); actor = 'b';
    pending.complete({'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket, 'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()});
    expect(await wait, isFalse); expect(c.hasValidTicket, isFalse);
    final d = InvoiceNoticeTicketController(actor: () => actor, session: () => session, now: () => start,
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket, 'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()});
    expect(await d.open(notice, invoiceId: invoice), isTrue); session = 'next'; expect(d.hasValidTicket, isFalse);
    expect(await d.open(notice, invoiceId: invoice), isTrue); d.invalidate(); expect(d.hasValidTicket, isFalse);
  });

  test('approval dispatch consumes once and ambiguous errors never retry', () async {
    var calls = 0;
    final response = Completer<Object?>();
    final c = InvoiceNoticeTicketController(actor: () => 'a', session: () => 's', now: () => start,
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket,
        'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()},
      submitApproval: (id) { expect(id, ticket); calls++; return response.future; });
    expect(await c.open(notice, invoiceId: invoice), isTrue);
    final first = c.approve();
    expect(await c.approve(), InvoiceNoticeApprovalResult.notSubmitted);
    expect(await c.open(notice, invoiceId: invoice), isFalse);
    response.completeError(StateError('connection lost after commit'));
    expect(await first, InvoiceNoticeApprovalResult.unconfirmed);
    expect(await c.approve(), InvoiceNoticeApprovalResult.notSubmitted);
    expect(calls, 1);
  });
  test('late approval from an old actor or invalidated lifecycle is never success', () async {
    var actor = 'a';
    final response = Completer<Object?>();
    final c = InvoiceNoticeTicketController(actor: () => actor, session: () => 's', now: () => start,
      openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket,
        'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()},
      submitApproval: (_) => response.future);
    expect(await c.open(notice, invoiceId: invoice), isTrue);
    final first = c.approve();
    actor = 'b'; c.invalidate(); response.complete(true);
    expect(await first, InvoiceNoticeApprovalResult.unconfirmed);
  });
  test('only exact server true confirms the approval', () async {
    for (final result in [true, false, null, 'true', {'approved': true}]) {
      final c = InvoiceNoticeTicketController(actor: () => 'a', session: () => 's', now: () => start,
        openTicket: (_) async => {'notification_id': notice, 'invoice_id': invoice, 'ticket_id': ticket,
          'expires_at': start.add(const Duration(minutes: 5)).toIso8601String()},
        submitApproval: (_) async => result);
      expect(await c.open(notice, invoiceId: invoice), isTrue);
      expect(await c.approve(), result == true ? InvoiceNoticeApprovalResult.confirmed : InvoiceNoticeApprovalResult.unconfirmed);
    }
  });
}
