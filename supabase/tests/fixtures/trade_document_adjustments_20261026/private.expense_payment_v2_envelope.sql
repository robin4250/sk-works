CREATE OR REPLACE FUNCTION private.expense_payment_v2_envelope(cid uuid, doc uuid, subject uuid, day date, revision integer, amount numeric, claims jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare row jsonb; minimal jsonb:='[]';seen uuid[]:='{}';identifier uuid;total numeric:=0;
begin
 if cid is null or doc is null or subject is null or day is null or revision is null or revision<1
 or amount is null or amount<0 or amount<>trunc(amount) or amount>9007199254740991
 or jsonb_typeof(claims) is distinct from 'array' then raise exception 'invalid payment expense v2 envelope';end if;
 for row in select value from jsonb_array_elements(claims) loop
 if jsonb_typeof(row) is distinct from 'object' or jsonb_typeof(row->'id') is distinct from 'string'
 or jsonb_typeof(row->'revision') is distinct from 'number' or (row->>'revision')!~'^[1-9][0-9]*$'
 or jsonb_typeof(row->'amount_yen') is distinct from 'number' or (row->>'amount_yen')!~'^[1-9][0-9]*$'
 or (row->>'amount_yen')::numeric>9007199254740991 then raise exception 'invalid v2 original claim';end if;
 identifier:=(row->>'id')::uuid;
 if identifier=any(seen) then raise exception 'duplicate v2 claim';end if;
 seen:=array_append(seen,identifier);total:=total+(row->>'amount_yen')::numeric;
 if total>9007199254740991 then raise exception 'v2 original amount overflow';end if;
 minimal:=minimal||jsonb_build_array(jsonb_build_object('id',identifier,'revision',(row->>'revision')::integer,'amount_yen',(row->>'amount_yen')::bigint));
 end loop;
 if total<>amount then raise exception 'v2 original amount differs';end if;
 return jsonb_build_object('version',2,'contract','expense_cost_direction','document_kind','paymentCertificate','direction','deduction',
 'company_id',cid,'document_id',doc,'subject_id',subject,'month',to_char(day,'YYYY-MM'),'document_revision',revision,'amount_yen',amount,'claims',minimal);
end $function$;

