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
}
