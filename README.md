# SKO

SKO is a Flutter-based company and work management app. The product brand is centralized in code so customer-facing naming can evolve without renaming compatibility-sensitive persistence, package, backend, or integration identifiers.

## Current prototype

The app currently includes interactive prototype screens for:

- Employees and partner companies
- Qualification management
- Site/project management
- Attendance and man-day tracking
- Invoice management
- Company/master settings

Each module currently supports list display, search, record creation, detail viewing, and deletion using in-memory sample data.

## Important current limitation

Data is not persisted yet. Records added in the prototype are cleared when the app is restarted. Persistent storage, authentication, cloud sync, document/photo storage, detailed invoicing calculations, and production permissions will be added in later stages.

## Build

Codemagic configuration is included in `codemagic.yaml`. The workflow creates the native iOS/Android project files, gets packages, analyzes the project, runs tests, and builds an unsigned iOS release app.
