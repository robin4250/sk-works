alter table public.attendance_verifications
  drop constraint if exists attendance_verifications_verification_mode_check;

alter table public.attendance_verifications
  add constraint attendance_verifications_verification_mode_check
  check (
    verification_mode in (
      'manual',
      'location',
      'gps_auto',
      'location_photo'
    )
  );
