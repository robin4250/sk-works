# SKO

SKO is a Flutter-based company and work management app. The customer-facing brand is centralized so naming can evolve without renaming compatibility-sensitive package, database, backend, or integration identifiers.

## Current implementation

The app now includes authenticated Supabase-backed workflows for:

- Employees / partner companies
- Qualifications and certificate photos
- Sites / projects
- Attendance and optional verification
- Customer / site-level invoice data
- Site/company communication groups and realtime chat
- Notes and photo albums
- LINE webhook staging, explicit LINE-group binding, and LINE attendance previews
- Required-document checks
- Company settings and October rollout readiness

Local storage remains only for prototype/offline-compatible paths and lightweight preferences where applicable.

## Production safety

- Company data is scoped through Supabase RLS and company membership.
- LINE groups remain pending until an owner/admin explicitly proves control and activates a binding.
- LINE-derived attendance remains candidate/preview data until identities and work records are confirmed.
- Disabling an optional module hides the workflow without deleting its historical data.
- Sensitive service-role webhook writes remain server-side.

## Brand compatibility

The product name shown to users is **SKO**. Internal compatibility identifiers such as the Dart package name `sk_works`, repository name, persistence keys, database identifiers, webhook URLs, and environment variable names are intentionally migrated only when a compatibility plan exists.

## Build

GitHub Actions / Flutter CI analyzes the project, runs tests, and builds an Android debug APK for validation. Additional release workflows can be added when distribution credentials and release targets are finalized.
