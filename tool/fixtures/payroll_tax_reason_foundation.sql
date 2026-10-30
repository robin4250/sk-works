-- Synthetic prerequisites only. The saver, validator and SID checker are loaded
-- byte-for-byte from read-only captured deployed definitions in the next file.
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA payroll_tax_private;
GRANT USAGE ON SCHEMA public,auth,private,payroll_tax_private TO anon,authenticated,service_role;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
CREATE FUNCTION private.account_access_allowed() RETURNS boolean LANGUAGE sql STABLE AS $$SELECT current_setting('fixture.blocked',true) IS DISTINCT FROM '1'$$;
CREATE FUNCTION private.account_deletion_barrier_key(actor uuid) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$SELECT hashtextextended(actor::text,0)$$;
CREATE FUNCTION private.payroll_settings_allowed(cid uuid,wid uuid,mode text) RETURNS boolean LANGUAGE sql STABLE AS $$SELECT
 cid='10000000-0000-0000-0000-000000000001' AND wid='40000000-0000-0000-0000-000000000001'
 AND (auth.uid()='00000000-0000-0000-0000-000000000001' OR (mode='view' AND auth.uid()='00000000-0000-0000-0000-000000000003'))$$;
CREATE TABLE auth.users(id uuid PRIMARY KEY,is_anonymous boolean DEFAULT false,banned_until timestamptz);
CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid,not_after timestamptz);
INSERT INTO auth.users(id) VALUES('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000003');
INSERT INTO auth.sessions VALUES('70000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',null),('70000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',null),('70000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000003',null);
CREATE TABLE public.companies(id uuid PRIMARY KEY);
CREATE TABLE public.workers(id uuid PRIMARY KEY,company_id uuid);
INSERT INTO public.companies VALUES('10000000-0000-0000-0000-000000000001');
INSERT INTO public.workers VALUES('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
CREATE TABLE public.payroll_statements(company_id uuid,worker_id uuid,period_start date,workflow_state text,automatic_calculation boolean,detail jsonb);
CREATE TABLE payroll_tax_private.worker_conditions(company_id uuid,worker_id uuid,starts_on date,version bigint,value jsonb,updated_by uuid,updated_at timestamptz,PRIMARY KEY(company_id,worker_id,starts_on));
CREATE TABLE payroll_tax_private.condition_history(company_id uuid,worker_id uuid,starts_on date,version bigint,before_value jsonb,after_value jsonb,actor_id uuid,changed_at timestamptz,PRIMARY KEY(company_id,worker_id,starts_on,version));
ALTER TABLE payroll_tax_private.worker_conditions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_tax_private.condition_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON payroll_tax_private.worker_conditions,payroll_tax_private.condition_history FROM public,anon,authenticated;
CREATE FUNCTION payroll_tax_private.validate_basis_reference(v jsonb) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF v IS NOT NULL AND jsonb_typeof(v)<>'object' THEN RAISE EXCEPTION 'invalid fixture reference';END IF;END$$;
CREATE FUNCTION payroll_tax_private.verify_basis_reference(cid uuid,wid uuid,v jsonb) RETURNS void LANGUAGE plpgsql AS $$BEGIN PERFORM payroll_tax_private.validate_basis_reference(v);END$$;
CREATE FUNCTION payroll_tax_private.read_conditions(cid uuid,wid uuid) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE FUNCTION payroll_tax_private.conditions_save_reply(cid uuid,wid uuid,reference_sent boolean) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$BEGIN
 IF current_setting('fixture.rotate_session',true)='1' THEN
  PERFORM set_config('request.jwt.claims',jsonb_set(auth.jwt(),'{session_id}',to_jsonb('70000000-0000-0000-0000-000000000002'::text))::text,true);
 END IF;
 RETURN payroll_tax_private.read_conditions(cid,wid);
END$$;
CREATE FUNCTION private.refresh_automatic_payroll(cid uuid,wid uuid,day date) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
CREATE FUNCTION private.sync_payroll_attendance_detail(cid uuid,wid uuid,day date) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
