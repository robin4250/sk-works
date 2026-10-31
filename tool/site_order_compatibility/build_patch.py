"""Build review-only compatibility SQL from pinned catalog source, never apply it."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PINS = {
    'private.company_document_exchange(text,jsonb)': '3b5d4b6f7f83870bb548cdb3f950f43e',
    'private.save_company_delivery_items(text[])': 'e3ac57f00f6c4bf6e18f00e87c482b71',
    'private.send_site_share(uuid,uuid[])': '43e5cc748daadeca5011498d4e7019af',
    'private.site_share_inbox()': '092efa3b4009c7fc70d9d88424c4562d',
    'private.site_payment_pair(uuid,uuid)': '232f462a369a6ab76609bc82a8f5b146',
    'private.site_payment_agreement_targets(uuid)': '6fb428bb819041b1388aff0cb94ffb04',
}


def once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('exact source anchor changed')
    return source.replace(old, new)


def transform(signature, source):
    if hashlib.md5(re.search(r'AS \$function\$([\s\S]*)\$function\$', source).group(1).encode()).hexdigest() != PINS[signature]:
        raise ValueError('catalog function definition drift')
    if 'company_document_exchange' in signature:
        source = once(source,
            "from private.company_data_delivery_items i where i.delivery_id=(p_data->>'id')::uuid)",
            "from private.company_data_delivery_items i where i.delivery_id=(p_data->>'id')::uuid and i.payload_kind in ('qualification','personnel'))")
        anchor = " token:=(p_data->>'code')::uuid;"
        source = once(source, anchor, """
 -- Validate every received-data reference before delivery/code mutation.
 for x in select value from jsonb_array_elements(p_data->'items') loop
  if jsonb_typeof(x) is distinct from 'object' or jsonb_typeof(x->'kind') is distinct from 'string'
    or x->>'kind' not in ('received','received_data','worker_personnel','worker_qualification','company','archive','worker_document')
    or jsonb_typeof(x->'id') is distinct from 'string'
    or x->>'id' !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
   raise exception '送信データの種類を確認してください。' using errcode='22023';
  end if;
  if x->>'kind'='received_data' then
   if not exists (
    select 1 from private.company_data_delivery_items i
    join private.document_deliveries d on d.id=i.delivery_id
    where i.id=(x->>'id')::uuid and d.recipient_company_id=c
      and i.payload_kind in ('qualification','personnel')
   ) then raise exception 'このデータは個別の承認画面で確認してください。' using errcode='22023'; end if;
  end if;
 end loop;
""" + anchor)
        # A second predicate ensures the subsequent row read cannot copy an unsupported kind.
        source = once(source,
            "where i.id=(x->>'id')::uuid and d.recipient_company_id=c;\n   if not found then raise exception '再提出できる受領データがありません。';",
            "where i.id=(x->>'id')::uuid and d.recipient_company_id=c and i.payload_kind in ('qualification','personnel');\n   if not found then raise exception '再提出できる受領データがありません。';")
    elif 'save_company_delivery_items' in signature:
        # Repeat exact kind predicate for the mutation-loop read.
        source = once(source,
            'from private.company_data_delivery_items i\n        join private.document_deliveries d on d.id=i.delivery_id\n        where i.id=item_id and d.recipient_company_id=c',
            "from private.company_data_delivery_items i\n        join private.document_deliveries d on d.id=i.delivery_id\n        where i.id=item_id and d.recipient_company_id=c and i.payload_kind in ('qualification','personnel')")
        anchor = '  foreach k in array p_item_keys loop'
        source = once(source, anchor, """
  -- Preflight the complete batch before the first saved-item write.
  foreach k in array p_item_keys loop
    if k is null or k !~ '^(file|data):[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception '保存対象を確認してください。' using errcode='22023';
    end if;
    item_kind:=split_part(k,':',1); item_id:=split_part(k,':',2)::uuid;
    if item_kind='file' then
      if not exists(select 1 from private.document_delivery_items i
        join private.document_deliveries d on d.id=i.delivery_id
        where i.id=item_id and d.recipient_company_id=c) then
        raise exception '保存できない書類が含まれています。' using errcode='22023';
      end if;
    else
      if not exists(select 1 from private.company_data_delivery_items i
        join private.document_deliveries d on d.id=i.delivery_id
        where i.id=item_id and d.recipient_company_id=c
          and i.payload_kind in ('qualification','personnel')) then
        raise exception 'このデータは個別の承認画面で確認してください。' using errcode='22023';
      end if;
    end if;
  end loop;
""" + anchor)
    elif 'send_site_share' in signature:
        # Actual old definition has no successful non-INSERT/idempotent branch.
        source = once(source, '\nbegin\n', "\nbegin\n  raise exception '現場注文は専用の承認経路を使用してください。' using errcode='22023';\n")
    elif 'site_share_inbox' in signature:
        source = once(source, "      and i.payload_kind='site_share'",
            "      and i.payload_kind='site_share'\n      and not exists(select 1 from site_order_package_private.packages p where p.data_item_id=i.id)")
    elif 'site_payment_pair' in signature:
        source = once(source, ' select d.sender_company_id,d.recipient_company_id,',
            " if exists(select 1 from site_order_package_private.packages p where p.data_item_id=p_item) then\n  raise exception '現場注文は専用の承認経路を使用してください。' using errcode='22023';\n end if;\n select d.sender_company_id,d.recipient_company_id,")
    elif 'site_payment_agreement_targets' in signature:
        source = once(source, " where b.status='accepted' and i.payload_kind='site_share'",
            " where b.status='accepted' and i.payload_kind='site_share'\n and not exists(select 1 from site_order_package_private.packages p where p.data_item_id=b.data_item_id)")
    return source


def build():
    inputs = json.loads((ROOT / 'docs/review/site-order-compatibility/pinned-consumers.json').read_text())
    blocks = []
    for row in inputs:
        signature = row['signature']
        revised = transform(signature, row['definition'])
        # CREATE OR REPLACE from exact catalog source preserves OID, owner and ACL.
        blocks.append("""
 signature := %s;
 if to_regprocedure(signature) is null or md5(pg_get_functiondef(to_regprocedure(signature))) <> %s then
  raise exception 'compatibility dependency source drift: %%', signature;
 end if;
 if exists(select 1 from pg_proc p where p.oid=to_regprocedure(signature)
   and (p.proowner<>'postgres'::regrole or not p.prosecdef or p.proconfig is distinct from array['search_path=""']::text[]
     or p.proacl::text is distinct from %s)) then
  raise exception 'compatibility dependency owner/config/ACL drift: %%', signature;
 end if;
 select to_jsonb(p)-'prosrc' into before_attributes from pg_proc p where p.oid=to_regprocedure(signature);
 execute $replacement$%s$replacement$;
 if (select to_jsonb(p)-'prosrc' from pg_proc p where p.oid=to_regprocedure(signature)) is distinct from before_attributes then
  raise exception 'compatibility function attributes changed: %%', signature;
 end if;
""" % ("'" + signature + "'", "'" + hashlib.md5(row['definition'].encode()).hexdigest() + "'", ("'{postgres=X/postgres,authenticated=X/postgres}'" if ('company_document_exchange' in signature or 'site_payment_agreement_targets' in signature) else ("'{postgres=X/postgres}'" if 'site_payment_pair' in signature else 'null')), revised))
    return """-- REVIEW ONLY. Separate production approval required; feature remains OFF.
-- Install after package foundation; before any delivery mutation becomes reachable.
begin;
set local lock_timeout='2s';
set local statement_timeout='20s';
do $compatibility$
declare signature text; before_attributes jsonb; check_definition text;
begin
 if current_user<>'postgres' then raise exception 'owner deployment only'; end if;
 if to_regclass('site_order_package_private.packages') is null then raise exception 'package ownership dependency absent'; end if;
 lock table private.company_data_delivery_items in access exclusive mode;
 select pg_get_constraintdef(c.oid) into check_definition from pg_constraint c
 where c.conrelid='private.company_data_delivery_items'::regclass
 and c.conname='company_data_delivery_items_payload_kind_check'
 and c.contype='c' and c.convalidated and not c.connoinherit;
 if check_definition is distinct from 'CHECK ((payload_kind = ANY (ARRAY[''qualification''::text, ''personnel''::text])))' then
  raise exception 'payload-kind CHECK drift';
 end if;
""" + ''.join(blocks) + """
 alter table private.company_data_delivery_items drop constraint company_data_delivery_items_payload_kind_check;
 alter table private.company_data_delivery_items add constraint company_data_delivery_items_payload_kind_check
 check(payload_kind in ('qualification','personnel','site_share'));
end $compatibility$;
commit;
"""


if __name__ == '__main__':
    print(build(), end='')
