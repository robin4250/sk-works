# Supabase site sync

Authenticated Supabase builds use `SiteCloudPage` and `SiteCloudRepository` for site data.

- Sites are scoped by the current user's company membership.
- Customer names are resolved to `customers`; a missing customer is created automatically.
- Manager names are linked to matching employee workers when available.
- Site status values map between UI (`preparing`) and database (`preparation`).
- Non-Supabase builds keep the existing SharedPreferences prototype page for CI and isolated tests.
