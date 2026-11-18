begin;

-- Keep the current site acceptance function and its membership checks. Do not
-- choose an arbitrary billing customer when the incoming name has multiple matches.
do $migration$
declare
  definition text;
  previous text := $previous$    select id into customer_id
    from public.customers
    where company_id=c
      and (name=customer_name or billing_name=customer_name)
    order by created_at
    limit 1;

    if customer_id is null then$previous$;
  replacement text := $replacement$    select count(*), min(candidate.id::text)::uuid
      into customer_match_count, customer_id
    from public.customers candidate
    where candidate.company_id=c
      and (candidate.name=customer_name or candidate.billing_name=customer_name);

    if customer_match_count > 1 then
      customer_id := null;
    elsif customer_match_count = 0 then$replacement$;
begin
  definition := pg_get_functiondef('private.respond_site_share(uuid,boolean)'::regprocedure);
  if strpos(definition, previous) = 0
     or strpos(definition, '  customer_id uuid;') = 0 then
    raise exception '現場共有の承認処理が想定と異なります。既存定義を確認してください。';
  end if;
  definition := replace(definition, '  customer_id uuid;',
    E'  customer_id uuid;\n  customer_match_count bigint;');
  execute replace(definition, previous, replacement);
end
$migration$;

commit;
