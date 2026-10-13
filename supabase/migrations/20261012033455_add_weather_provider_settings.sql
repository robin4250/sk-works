-- Isolated provider choice: does not replace master_feature_settings or its CHECK.
create schema if not exists private;
create table if not exists private.weather_provider_settings (
 singleton boolean primary key default true check(singleton),
 provider text not null default 'openweather' check(provider in ('openweather','weatherkit')),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null
);
alter table private.weather_provider_settings enable row level security;
revoke all on private.weather_provider_settings from public, anon, authenticated;
insert into private.weather_provider_settings(singleton,provider) values(true,'openweather') on conflict(singleton) do nothing;
create or replace function private.read_weather_provider_setting()
returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'authentication required'; end if;
 return (select provider from private.weather_provider_settings where singleton);
end $$;
create or replace function private.write_weather_provider_setting(p_provider text)
returns text language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_current_user_master_admin() then raise exception 'master administrator required'; end if;
 if p_provider is null or p_provider not in ('openweather','weatherkit') then raise exception 'invalid weather provider'; end if;
 update private.weather_provider_settings set provider=p_provider,updated_at=now(),updated_by=auth.uid() where singleton;
 return private.read_weather_provider_setting();
end $$;
revoke all on function private.read_weather_provider_setting() from public,anon;
revoke all on function private.write_weather_provider_setting(text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.read_weather_provider_setting() to authenticated;
grant execute on function private.write_weather_provider_setting(text) to authenticated;
create or replace function public.current_weather_provider()
returns text language sql stable security invoker set search_path='' as $$ select private.read_weather_provider_setting(); $$;
create or replace function public.set_weather_provider(p_provider text)
returns text language sql security invoker set search_path='' as $$ select private.write_weather_provider_setting(p_provider); $$;
revoke all on function public.current_weather_provider() from public,anon;
revoke all on function public.set_weather_provider(text) from public,anon;
grant execute on function public.current_weather_provider() to authenticated;
grant execute on function public.set_weather_provider(text) to authenticated;
