-- Mirrors production migration 20261004110735.
-- The production fix disambiguates the requested month into v_period_start.
-- The preceding repository mirror already contains the corrected function body.
-- Keep this migration marker so repository history matches production history.

do $$
begin
  perform 1;
end
$$;
