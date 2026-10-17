# Personal account settings — 2026-10-17

The Settings page now provides a personal Account Settings entry, including when
company settings cannot be loaded. This does not bypass company permissions:
all company-setting errors and role checks remain unchanged.

The new page reads only the current user's Auth record using the captured JWT
and the existing secondary_password_configured boolean RPC with that exact JWT.
Any actor/token change rejects the response. Upstream error text, passwords,
hashes, tokens and identity subject values are not displayed or logged.
Backgrounding clears the personal snapshot; resuming reads it again.

Linked identities are shown separately from session amr evidence. OAuth amr does
not establish which linked provider performed the login. No provider is guessed.
Primary password configuration is explicitly unknown: the public Auth user
record does not expose its hash or a reliable password-configured field.
Secondary configuration errors are unknown, never false.

Phone confirmed_at is reported as Auth-server recorded confirmation, not proof
of current number ownership. Existing employee invitations use admin
phone_confirm and cannot be reused to claim an existing Google user's phone
was OTP verified. No number is added, auto-confirmed or assigned to another UID.
No SMS, sign-up, provider linking, password change, logout or Master operation
is performed by this feature.

Apple/Google/email/phone addition is shown as preparation only. Apple linking
needs its independent reviewed service, provider configuration and fresh
verification. Official phone update requires signed-in updateUser(phone), SMS
and verifyOTP(type phone_change). Paid SMS is prohibited for SKO; no equivalent
verified ownership mechanism has been established. Contact-number profile data,
Face/Touch success and email verification cannot be relabeled phone ownership.

Master-specific passwords, devices and recovery settings are not exposed here.
Existing Master-only settings keep their existing protected routes.
The page has its own ? help; shared manual_content is not modified.

Validation uses synthetic loopback SDK HTTP tests and widget tests. Real
provider linking, physical device biometric checks and phone enrollment are not
included or claimed complete.
