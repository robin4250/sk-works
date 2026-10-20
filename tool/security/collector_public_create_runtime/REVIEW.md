# Native collector permission-difference rehearsal candidate

**Root review required; not yet run on the native clone. No production changes. Do not repeat the failed original helper.**

Observed native clone has public owner pg_database_owner, database owner distinct from postgres, and public USAGE only for postgres. Production read-only observation has database owner postgres and effective CREATE=true. The original helper therefore encountered `permission denied for schema public` while installing public proof functions, before its intended scenario. This candidate preserves both original database ownership and the original stopped-source snapshot.

The new standalone helper copies the isolation, original catalog/row/sequence capture and complete rollback checks. It accepts only the reviewed existing supabase_admin database-owner role, SUPERUSER=true, LOGIN=true, PostgreSQL 17, installer USAGE=true and CREATE=false. It uses a local connection as that owner and first verifies actual ability to SET LOCAL SESSION AUTHORIZATION postgres and assume the three existing API roles. Failure stops without new existing-role membership. No credentials, network, mounted source or database-owner change is introduced.

The one outer transaction now:

1. As the already existing bootstrap owner, creates the new NOLOGIN collector test role and grants only its SET option to postgres (`SET TRUE, INHERIT FALSE, ADMIN FALSE`).
2. Grants CREATE on public only to postgres, matching the observed production effective capability. This is a clone-fixture correction, not a production permission proposal.
3. Uses **SET LOCAL SESSION AUTHORIZATION postgres**, so both session_user/current_user are postgres. A mere SET LOCAL ROLE would let the exact scenario's RESET ROLE return to bootstrap and would incorrectly exercise privileged code. The temporary original-function snapshot starts after this transition.
4. Loads the reviewed proof adjustment, exact original collector candidate and exact original scenario. Original runner role provisioning is moved once to step 1. Both gates start OFF; synthetic events only; no manufactured proof is inserted.
5. Executes ROLLBACK and compares all original catalog objects, schema/default/function ACLs, role memberships, data digests and sequences against the baseline. The bootstrap role and original database owner remain unchanged.

Separate source correction: production public default function privileges give service_role EXECUTE. Exactly three **new** public proof functions previously revoked only PUBLIC/anon, leaving that unwanted inherited service_role grant. The reviewed proof candidate additionally revokes service_role on reauthentication_capabilities, replace_secondary_password_with_proof and set_master_feature_enabled_with_proof. Issuer service_role EXECUTE remains allowed. Existing setter bodies, owners and ACLs remain byte-for-byte the original candidate; collector and scenario bytes/hashes are unchanged. Blanket default-privilege removal is not used.

Validation: two source/composition tests pass. A pinned PGlite 0.3.14 / PostgreSQL 17.5 focused permission fixture passes 14 checks: public CREATE failure reproduced, exact minimal transaction grant succeeds, inherited service_role EXECUTE reproduced and removed only for the three new functions, issuer permission preserved, new role SET-only options, RESET ROLE returns to installer, full composed candidate/scenario and complete baseline catalog/defaultACL/membership rollback. PGlite forbids demoting its bootstrap postgres, so the fixture explicitly maps the non-super installer to sko_fixture_installer. This is not native PostgreSQL 17.6.1.166 proof or proof of real Master authentication. Native completion remains pending.

Primary references:

- https://www.postgresql.org/docs/17/sql-set-session-authorization.html — LOCAL session authorization requires the initially authenticated superuser and lasts for the transaction.
- https://www.postgresql.org/docs/17/sql-set-role.html — RESET ROLE returns to session user; ability to SET ROLE is checked against session user.
- https://www.postgresql.org/docs/17/sql-grant.html — role SET/INHERIT/ADMIN options and schema CREATE grants.

No existing role attributes, original database owner or production ACLs should be changed to make this pass. Any different native owner/version/permission contract must stop for review.
