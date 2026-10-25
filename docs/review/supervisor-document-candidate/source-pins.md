# Exact source pins

Base: `8f3d881e06847ff9fdfb81d49d78884206ec17f7`.

- `shared_daily_report_private.signature_scope(uuid)`: body MD5 `a03fa2df7e85bb5cf3b27015b4dfea84`
- `shared_daily_report_private.enroll_work_report(uuid)`: body MD5 `1d6e27d3749d4abd788cea1566139236`
- `shared_daily_report_private.collect_supervisor(uuid,uuid,text,jsonb,boolean,timestamp with time zone,text)`: body MD5 `c6960ce9a46cdfb73a25a98ab8313720`
- `shared_daily_report_private.manage_signature(uuid,text,text,jsonb,timestamp with time zone,text)`: body MD5 `a26c6c0868c3bb2690421abe280afc59`
- `private.save_daily_report_signature(uuid,text,text,jsonb)`: body MD5 `40f29d53008e6bf5610ce25e5fa96ef3`
- `shared_daily_report_private.guard_report()`: body MD5 `e00cb19ae8c25b03e0e57041df8aa9fe`
- `shared_daily_report_private.guard_roster()`: body MD5 `99fda6eb942b96734aa21cd0646a6caa`
- `shared_report_edit_private.collect_supervisor(uuid,uuid,text,jsonb,timestamp with time zone,text)`: body MD5 `b1eb97d6c01a75fd22ab1cf8a2a29711`
- `shared_report_edit_private.copy_unchanged_after_reporter()`: body MD5 `e093579361a8c6b7ffab4886c9cd6a08`
- `shared_report_edit_private.complete_edit()`: body MD5 `ebb0cadb1d81814031f27fa8fe580cda`
- `shared_daily_report_private.record_signature()`: body MD5 `97d4fd61705058afbaed29c0a1ffaf49`

private.save_daily_report_signature comes from the exact-main actual-source fixture; MD5 40f29d53008e6bf5610ce25e5fa96ef3 agrees with checkout_shared_managed_source prerequisite. Other definitions come from exact-main candidates. Full live catalog/source equality is still required before deployment.
