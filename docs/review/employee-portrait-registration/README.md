# Employee portrait registration composition

The actual employee-detail route previously displayed the portrait from the
current submitted/verified worker-document row but offered no picker/save entry.
This candidate supplies a selected employee/company page and repository. The
separate detail-page owner adds the entry and reload hook; this source alone
does not claim that hook is integrated.

The page reuses the existing photo draft editor and managed-document upload/CAS
API. One new image (maximum 6 MiB) becomes the primary attachment, and all former
paths remain retained. The new image is submitted with original verification
false; it is not presented as already verified. Existing metadata/notes and
expiry survive, and no Storage overwrite/delete occurs. A stale row, denied
Storage, changed Auth history, company or personnel permission prevents success.
The optional managed-save scope callback only adds checks to the original actor,
company, active-worker/requirement and row/CAS checks; old callers omit it.

A missing active portrait requirement is not silently created. An explicit entry
opens the existing requirement settings, where a permitted administrator can add
an internal, optional, no-expiry face-photo item, then return and reload. No
production rows, images or settings were accessed or created during development.
Feature/Storage denial and missing backend schema remain separate blockers.

Validation uses the real pinned SDK and loopback HTTP fixtures for the existing
managed upload/metadata pipeline, plus widget selection/cancel/settings cases.
The fixture read-model adapter supplies only synthetic selected roster and
requirements; it does not establish production RLS or actual camera/gallery
permissions. CI results are pending. Real device selection, deployed capability,
Storage policy and final detail hook integration must be checked separately.

Read-only production catalog observation (no business rows/paths/images): the
attachment_paths text[] column, managed Storage INSERT/SELECT policies, and
portrait read RPC exist. This does not prove upload success or all restrictive
policies/capabilities. No schema preparation or production mutation was applied.
The existing managed route uses schema availability and management/row checks;
no unrelated first-photo licence capability or master gate is reused/bypassed.

Official Storage access-control and Dart uploadBinary documentation were checked:
https://supabase.com/docs/guides/storage/security/access-control and
https://supabase.com/docs/reference/dart/file-buckets-upload . Existing
FileOptions(upsert:false) remains unchanged; no UPDATE/DELETE policy is added.

The repository binds its first personnel privacy epoch for its entire lifetime;
a later load cannot adopt a new epoch and revive an old pending save. It also
captures the existing read-only AppAuthMutationGateway admission. Logout intent
or failure blocks work while the SDK token can still be present. No shared Auth
code is edited. Dedicated regressions hold the logout persistence intent and an
old read across a background/foreground epoch change, requiring zero writes.
