alter table public.company_module_settings
  drop constraint if exists company_module_settings_module_key_check;

alter table public.company_module_settings
  add constraint company_module_settings_module_key_check
  check (
    module_key = any (
      array[
        'qualifications'::text,
        'documents'::text,
        'attendance'::text,
        'sites'::text,
        'chat'::text,
        'notes'::text,
        'albums'::text,
        'invoices'::text,
        'line_bridge'::text,
        'vehicle_routes'::text
      ]
    )
  );
