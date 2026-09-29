# SKO country-pack structure

Japan is treated as the first country pack, not as hard-coded global behavior.

- `lib/international/core/`: country-neutral contracts.
- `lib/international/countries/jp/`: Japan-only language, currency, date, phone and legal-document configuration.
- Future markets add sibling folders such as `countries/us/` or `countries/sg/`.
- `active_country_pack.dart`: selects the production pack.

New country-specific rules should be placed in the country folder when they differ by jurisdiction. Shared attendance, approval, chat, company and security workflows remain in the existing core/features layers.

Migration rule: move Japan-specific constants gradually and keep each move behavior-preserving with tests. Do not perform a single high-risk rewrite before TestFlight.
