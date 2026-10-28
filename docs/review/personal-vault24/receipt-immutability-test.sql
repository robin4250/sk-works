\set ON_ERROR_STOP on
-- Run after catalog-test.sql or read-api-test.sql in the same isolated database.
\i docs/review/personal-vault24/receipt-immutability.sql.review-only
set fixture.actor='00000000-0000-0000-0000-000000000001';set fixture.live='true';set fixture.enabled='true';
do $$declare
 mid uuid:='10000000-0000-0000-0000-000000000003';cid uuid:='20000000-0000-0000-0000-000000000001';wid uuid:='30000000-0000-0000-0000-000000000001';rid uuid:='40000000-0000-0000-0000-000000000003';sid uuid:='50000000-0000-0000-0000-000000000001';a text:=repeat('c',64);b text:=repeat('b',64);p text;
begin
 p:='personal-vault/'||auth.uid()::text||'/'||a||'.pdf';
 perform personal_vault24_candidate.start_manifest(mid,cid,wid,rid,a,b,1);
 begin update personal_vault24_candidate.manifests set status='complete',completed_at=now() where id=mid;raise exception 'test_expected_incomplete';exception when others then if sqlerrm<>'vault_manifest_immutable' then raise;end if;end;
 begin update personal_vault24_candidate.manifests set owner_id='00000000-0000-0000-0000-000000000002' where id=mid;raise exception 'test_expected_owner';exception when others then if sqlerrm<>'vault_manifest_immutable' then raise;end if;end;
 begin delete from personal_vault24_candidate.manifests where id=mid;raise exception 'test_expected_manifest_delete';exception when others then if sqlerrm<>'vault_manifest_immutable' then raise;end if;end;
 begin insert into personal_vault24_candidate.items values(mid,a,'own_payroll',sid,'r1',a,'personal-vault/00000000-0000-0000-0000-000000000002/'||a||'.pdf','v1',b,42);raise exception 'test_expected_foreign_path';exception when others then if sqlerrm<>'vault_path_rejected' then raise;end if;end;
 perform personal_vault24_candidate.record_item(mid,a,'own_payroll',sid,'r1',a,p,'v1',b,42);
 begin update personal_vault24_candidate.items set pdf_hash=repeat('d',64) where manifest_id=mid;raise exception 'test_expected_update';exception when others then if sqlerrm<>'vault_receipt_immutable' then raise;end if;end;
 begin delete from personal_vault24_candidate.items where manifest_id=mid;raise exception 'test_expected_delete';exception when others then if sqlerrm<>'vault_receipt_immutable' then raise;end if;end;
 perform personal_vault24_candidate.seal_manifest(mid,array[a]);
 perform personal_vault24_candidate.seal_manifest(mid,array[a]);
 perform personal_vault24_candidate.record_item(mid,a,'own_payroll',sid,'r1',a,p,'v1',b,42);
 begin update personal_vault24_candidate.manifests set status='pending',completed_at=null where id=mid;raise exception 'test_expected_reopen';exception when others then if sqlerrm<>'vault_manifest_immutable' then raise;end if;end;
 begin update personal_vault24_candidate.manifests set completed_at=completed_at+interval '1 second' where id=mid;raise exception 'test_expected_time';exception when others then if sqlerrm<>'vault_manifest_immutable' then raise;end if;end;
 begin insert into personal_vault24_candidate.items select mid,repeat('d',64),'own_attendance',sid,'r1',a,'personal-vault/'||auth.uid()::text||'/'||repeat('d',64)||'.pdf','v2',b,42;raise exception 'test_expected_late_insert';exception when others then if sqlerrm<>'vault_receipt_parent_rejected' then raise;end if;end;
 begin truncate personal_vault24_candidate.items;raise exception 'test_expected_truncate';exception when others then if sqlerrm<>'vault_receipt_truncate_rejected' then raise;end if;end;
 begin truncate personal_vault24_candidate.manifests cascade;raise exception 'test_expected_truncate_manifest';exception when others then if sqlerrm<>'vault_receipt_truncate_rejected' then raise;end if;end;
 assert (select pdf_hash=b and object_version='v1' from personal_vault24_candidate.items where manifest_id=mid);
 assert (select status='complete' and owner_id=auth.uid() from personal_vault24_candidate.manifests where id=mid);
 assert not has_function_privilege('authenticated','personal_vault24_candidate.protect_item_receipt()','EXECUTE');
end $$;
