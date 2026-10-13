# SKO phone authentication setup

The app supports phone-number login and admin registration with SMS OTP.

## Required Supabase dashboard settings before device testing

1. Open Authentication -> Providers.
2. Enable Phone.
3. Configure a supported SMS provider for the project.
4. Keep phone confirmation enabled for new registrations.
5. Confirm the provider can deliver OTP messages to Japanese +81 mobile numbers.

The connected Supabase management tools used during pre-device preparation do not expose a write action for hosted Auth provider settings, so these provider settings must be confirmed in the Supabase Dashboard.

## Accepted SKO phone IDs

SKO accepts Japanese mobile numbers using the 070, 080, and 090 prefixes, including common formatting such as:

- 09012345678
- 090-1234-5678
- +81 90 1234 5678

The app normalizes supported numbers to E.164 form before sending them to Supabase and rejects malformed values or non-mobile Japanese numbers before signup/login.

## Registration flow

1. Mobile number (ID)
2. Main password
3. Main password confirmation
4. SMS OTP
5. Secondary password for sensitive information
6. Optional Face ID / Touch ID enrollment
7. User/company/invoice bank details
8. Home

## SMS verification resilience

- The registration request explicitly uses the SMS channel.
- The OTP screen supports resending the signup SMS.
- Supabase rate-limit errors are shown with a user-friendly wait-and-retry message.
- Invalid or expired OTP errors tell the user to resend and enter the newest code.
- Missing SMS provider/configuration errors are translated into an actionable setup message.
- Already-registered numbers direct the user back to login.

Supabase applies OTP request rate limits, so repeated resend attempts should not be hammered continuously.

## Existing accounts

Legacy email/password accounts remain supported through the existing-email-account login option.

## Secondary password

The secondary password is never stored as plaintext. It is hashed in PostgreSQL with pgcrypto through narrow SECURITY DEFINER RPC functions.

After five consecutive failures, verification is temporarily locked for five minutes.

## iOS note

The iOS project, permission descriptions, Bundle Identifier, signing diagnostics, and device launch helpers are generated/validated by the scripts under `tool/`.

On the Mac, use:

```bash
bash tool/mac_first_run.sh
bash tool/ios_install_assistant.sh
bash tool/run_ios_device.sh
```

If device installation fails, collect a sanitized diagnostic report with:

```bash
bash tool/collect_ios_diagnostics.sh
```
