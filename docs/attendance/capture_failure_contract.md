# GPS + photograph capture failure contract

This opt-in database contract does not enable any company and does not repair or infer old evidence. The migration is not applied to production by this change.

For a newly captured `location_photo` attendance row, send `capture_contract_version: 1` and both explicit statuses. Keep the requested method; a failure is never relabelled as manual attendance.

| Column | Contract |
| --- | --- |
| `gps_capture_status` | `acquired`, `failed`, `missing` |
| `photo_capture_status` | `uploaded`, `upload_failed`, `failed`, `missing` |
| `gps_captured_at` | Actual GPS sample timestamp, required for acquired GPS |
| `photo_captured_at` | Actual shutter timestamp from verified native/EXIF evidence; NULL when unknown |
| `photo_observed_at` | Camera return/observation timestamp, required for uploaded or upload_failed; never labelled shutter time |
| `captured_address` | Address obtained for that actual GPS sample; NULL when GPS failed/missing |

GPS failure/missing requires NULL coordinates, accuracy, site distance, sample timestamp and address, with `proximity_status: not_checked`. Photo upload failure retains its observation timestamp and any known actual shutter timestamp but has no server storage path. Failure metadata is recorded evidence, not successful upload evidence. No timestamp/address is invented from a later sample or `confirmed_at`.

`get_attendance_capture_capability(p_company_id)` returns version, company ID and `capture_enabled`. Missing RPC or any response error must leave the client OFF. The getter requires existing company membership and active-account access; it grants no management powers. Only the private rollout table controls enabling. No client enabling endpoint exists.

All new-contract evidence metadata, GPS values, mode and stored-photo path are immutable. Existing shift guards still manage chronology, source IDs, company/site/route/vehicle and canonical work date. Daily-report association remains allowed. Legacy metadata-NULL rows retain their original GPS/photo requirements and photograph-linking behavior.

## Verification

Run:

```
node tool/verify_attendance_capture_failure.mjs /path/to/@electric-sql/pglite/dist/index.js
```

The verifier first runs the existing GPS/RLS assertions, then tests OFF rejection, scoped readiness, failure recording across month-end with explicit source linkage, successful GPS/photo capture, honest unknown shutter timestamps with recorded observation time, immutable evidence and actual timestamps, a NULL-version bypass rejection, foreign-worker rejection, blocked-account rejection, and existing management chronology behavior. It uses synthetic fixtures, including a fixture-only UPDATE policy to exercise the trigger. It does not change production RLS.

## Remaining work

The client must display failure and offer retake/confirmation, preserve actual GPS timestamps and distinguish observed photograph return time from any verified shutter timestamp, and use the getter before sending new columns. Daily-report readers must display explicit missing/failure states even when no photo path exists. A durable local photo queue and later controlled upload attachment are separate work: this contract intentionally does not allow rewriting failed evidence into a successful capture. Production readiness and physical-device behavior are not established by the SQL fixture.
