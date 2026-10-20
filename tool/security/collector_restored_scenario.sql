-- Isolated restored DB, same outer transaction. Synthetic events only.
DO $collector_restored_checks$
DECLARE event jsonb; rejected boolean; actual uuid; expected uuid:='00000000-0000-0000-0000-000000000010'; r text;
BEGIN
 IF EXISTS(SELECT 1 FROM private.security_collector_control WHERE ingest_enabled OR read_enabled)
 THEN RAISE EXCEPTION 'collector must start OFF'; END IF;
 event:=jsonb_build_object('event_id',expected,'collector_id','00000000-0000-0000-0000-000000000020',
 'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'event_kind','current_lure_touched','generation',1,'correlation_key',repeat('a',64),
 'key_epoch',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD'));
 -- Even the bridge cannot ingest while OFF.
 EXECUTE 'SET LOCAL ROLE sko_security_collector_ingest'; rejected:=false;
 BEGIN PERFORM private.ingest_security_collector_event(event);
 EXCEPTION WHEN SQLSTATE '55000' THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'OFF ingest accepted event'; END IF;
 EXECUTE 'RESET ROLE';
 -- Test-only activation, rolled back. No real collector identities or credentials.
 UPDATE private.security_collector_control SET ingest_enabled=true;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  EXECUTE format('SET LOCAL ROLE %I',r); rejected:=false;
  BEGIN PERFORM private.ingest_security_collector_event(event);
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'API role can ingest'; END IF;
  rejected:=false;
  BEGIN PERFORM 1 FROM private.security_collector_events;
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'API role can read collector table'; END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
 EXECUTE 'SET LOCAL ROLE sko_security_collector_ingest';
 actual:=private.ingest_security_collector_event(event);
 IF actual IS DISTINCT FROM expected OR private.ingest_security_collector_event(event) IS DISTINCT FROM actual
 THEN RAISE EXCEPTION 'same event retry changed receipt'; END IF;
 rejected:=false;
 BEGIN PERFORM private.ingest_security_collector_event(event||'{"generation":2}');
 EXCEPTION WHEN unique_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'altered retry accepted'; END IF;
 rejected:=false;
 BEGIN PERFORM private.ingest_security_collector_event(event||'{"raw_ip":"synthetic-invalid-field"}');
 EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'unapproved metadata accepted'; END IF;
 rejected:=false;
 BEGIN PERFORM private.ingest_security_collector_event(event||'{"occurred_at":"2000-01-01T00:00:00.000Z","key_epoch":"2000-01-01"}');
 EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'stale event accepted'; END IF;
 rejected:=false;
 BEGIN PERFORM 1 FROM private.security_collector_events;
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'bridge can read event table'; END IF;
 rejected:=false;
 BEGIN PERFORM private.read_security_collector_events('synthetic-no-proof');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'bridge can read master records'; END IF;
 EXECUTE 'RESET ROLE';
 IF (SELECT count(*) FROM private.security_collector_events)<>1
 OR (SELECT count(*) FROM private.security_collector_read_audit)<>0
 THEN RAISE EXCEPTION 'event or audit counts differ'; END IF;
 -- Do not stub the restored account/master/proof functions to claim real auth.
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claims','{}',true);
 EXECUTE 'SET LOCAL ROLE authenticated'; rejected:=false;
 BEGIN PERFORM private.read_security_collector_events('synthetic-no-proof');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'anonymous actor can read master records'; END IF;
 EXECUTE 'RESET ROLE';
 UPDATE private.security_collector_control SET ingest_enabled=false,read_enabled=false;
 IF EXISTS(SELECT 1 FROM private.security_collector_control WHERE ingest_enabled OR read_enabled)
 THEN RAISE EXCEPTION 'collector test did not return OFF'; END IF;
END $collector_restored_checks$;
