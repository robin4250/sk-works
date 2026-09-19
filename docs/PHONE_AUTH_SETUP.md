# SKO phone authentication setup

The app code supports phone-number login and admin registration with SMS OTP.

## Required Supabase dashboard settings before device testing

1. Open Authentication -> Providers.
2. Enable Phone.
3. Configure a supported SMS provider for the Supabase project.
4. Keep phone confirmation enabled for new registrations.
5. Confirm the project can send OTP messages to Japanese +81 numbers.

The SKO registration screen accepts common Japanese mobile formatting such as:

- 09012345678
- 090-1234-5678
- +819012345678

The app normalizes domestic numbers to E.164 form before sending them to Supabase.

## Registration flow

1. Mobile number (ID)
2. Main password
3. Main password confirmation
4. SMS OTP
5. Secondary password for sensitive information
6. Optional Face ID / Touch ID enrollment
7. User/company/invoice bank details
8. Home

## Existing accounts

Legacy email/password accounts remain supported through the "existing email account" login option.

## Secondary password

The secondary password is never stored as plaintext. It is hashed in PostgreSQL with pgcrypto through SECURITY DEFINER RPC functions.

After five consecutive failures, verification is temporarily locked for five minutes.

## iOS note

Face ID / Touch ID uses the Flutter local_auth package. The repository currently does not contain the generated iOS platform project. When the Mac/Xcode stage creates or restores the iOS project, add the required Face ID usage description to Runner/Info.plist and verify signing/capabilities before device installation.
