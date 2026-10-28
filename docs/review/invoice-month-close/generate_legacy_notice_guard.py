#!/usr/bin/env python3
"""Generate a review-only old-notice suppression candidate from exact sources."""
import hashlib
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
out = pathlib.Path(sys.argv[2])

def extract(name, expected):
    start = text.index('CREATE OR REPLACE FUNCTION '+name+'(')
    end = text.index('$function$;', start) + len('$function$;')
    definition = text[start:end]
    body = definition.split('AS $function$', 1)[1].rsplit('$function$;', 1)[0]
    if hashlib.md5(body.encode(), usedforsecurity=False).hexdigest() != expected:
        raise ValueError('legacy notification body drift: '+name)
    return definition

def one(value, old, new):
    if value.count(old) != 1:
        raise ValueError('legacy notification anchor changed')
    return value.replace(old, new, 1)

trigger = extract('private.invoice_approval_rows_trigger', '5b978081e432d0dbf3b8403c293a4646')
due = extract('public.enqueue_due_invoice_approval_notifications', '397e4d08e3fdda359ddf35a4d7e3a9f6')
trigger = one(trigger, '  if new.billing_period_end <=', '  if not invoice_month_close_candidate.notification_rollout_enabled() and new.billing_period_end <=')
due = one(due, "  if v_uid is null then raise exception 'authentication required'; end if;", "  if v_uid is null then raise exception 'authentication required'; end if;\n  if invoice_month_close_candidate.notification_rollout_enabled() then return 0;end if;")
out.write_text('-- Generated review only; do not install in production.\n'+trigger+'\n'+due+'\n')
