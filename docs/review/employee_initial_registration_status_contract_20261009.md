# Initial registration status and delivery history (staged OFF)

Existing `employee_registration_invites.status = approved` together with non-NULL `approved_at` is completion evidence. `password_changed_at` proves the initial password step only; `approval_pending` is awaiting administrator approval. `workers.user_id` is populated by invite creation and is never completion evidence.

The new exact-company owner/admin RPC returns no phone, password, QR payload, token, or auth user ID. It does not alter the existing list RPC, invitation creation, approval, role, Auth, or RLS policies. Its private per-company gate defaults OFF, with no migration backfill/activation. Existing source-notification eligibility excludes inactive/restricted callers; this dependency must be deployed before use.

Delivery history is separate: `manual_sent` requires an explicit administrator confirmation and means “administrator recorded manual sending”, not provider delivery/receipt. `unknown` remains unknown. Opening an SMS composer, cancelling, sharing a QR, or having a linked user ID must never create `manual_sent` automatically. Event UUIDs are fixed before retry; the same UUID/payload is idempotent, while a changed identity is rejected. Client roles cannot read or mutate the private history table.

`create-employee-invite` rejects an already linked worker. No existing secure reissue endpoint or secret retrieval contract was found. This change deliberately does not retrieve old temporary passwords or create another Auth user. For an already-created invitation with no securely available guidance, show the state and block a new invite instead of claiming a usable resend. Secure reissue/resend remains unfinished.

Synthetic PGlite checks cover OFF, admin/company separation, NULL approval timestamp, pending approval, linked user not complete, explicit manual confirmation, unknown history, and fixed event identity. Production application/activation and actual delivery/device operation are unverified.
