# R27 existing analysis-group creation ordering verification

This is a test/document-only change: three new files and **no product SQL patch**.
It avoids adding a redundant staging mechanism where the observed existing path
already creates an isolated participant-only room. Production operations were
catalog/source/trigger metadata SELECTs only; no business rows or credentials.

The exact create_line_history_analysis body (MD5 a2b8073b520abf133e6ce958e5f8c7f6)
requires existing Master/LINE access, one selected company and invoice permission.
It calls the exact create_custom_chat_group body (ab890a5257750f8850297016bb4ec712),
which creates participants_only=true and inserts only its creator as a member.
Only after that does it create the durable analysis lineage row. Neither body
inserts an invitation, notification or initial message.

Read-only trigger inventory found three communication_groups triggers:
record_chat_creator BEFORE INSERT/UPDATE (creator fixed to current actor),
keep_chat_visibility BEFORE UPDATE and guard_standard_company_chat BEFORE
DELETE/UPDATE. No noninternal communication_group_members trigger was present.
Their exact source definitions are preserved in the fixture and hash-checked.

The disposable fixture executes those actual two creation bodies and all three
triggers. A fixture-only member-insert observer records the pre-lineage moment:
creator Master can access, ordinary same-company user and another enabled but
nonparticipating Master cannot, and durable lineage is not yet present. After
creation, only creator membership exists, no initial message or group notice is
created, same command ID returns the original group, and ordinary custom-chat
creation by a general user still works.

The fixture replaces the earlier generic test's permissive company-scope SELECT
and synthetic FOR ALL policy *only inside the disposable test* with the observed
real group SELECT predicate can_access_communication_group. A FOR ALL policy also
grants SELECT; retaining that artificial policy would misrepresent production.
The temporary overlay is restored exactly before prior policy snapshots are
compared. No production policy change is included in R27.

LINE access and public Master identity helpers are explicit fixture helpers;
source company/friend/profile rows are synthetic. Real GoTrue, feature-control
configuration, session revocation and UI are not end-to-end validated here.
PG17/PostgREST CI must independently verify the same original private creation via
a fixture wrapper: non-Master 403, Master success/idempotence, ordinary and
nonparticipant-Master REST SELECT empty. These wrappers/observers are not product
APIs. Existing source behaviour is verified only for this bounded creation path.

The invoice creation-before-lineage issue addressed by R25 is a distinct path
with an actual approval/notification trigger. R27 must not be used to dismiss
that issue, unknown provenance, other site/member writers, moderation payloads,
cached copies, external push, Storage delivery or production restore/UI gates.
No broad TestFlight security approval follows from this test-only finding.
