alter table public.attendance_entries
  add column if not exists signer_name text,
  add column if not exists signature_json jsonb,
  add column if not exists signed_at timestamptz;

comment on column public.attendance_entries.signer_name is
  '現場責任者など、出勤記録へ共通サインした人の表示名';
comment on column public.attendance_entries.signature_json is
  'SignatureCapturePage の正規化済み筆跡データ';
comment on column public.attendance_entries.signed_at is
  '出勤記録へサインを確定した日時';
