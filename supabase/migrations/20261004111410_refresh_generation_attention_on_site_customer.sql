drop trigger if exists site_customer_refresh_generation_setting_issues on public.sites;

create trigger site_customer_refresh_generation_setting_issues
after update of customer_id on public.sites
for each row execute function private.refresh_generation_setting_issues_trigger();
