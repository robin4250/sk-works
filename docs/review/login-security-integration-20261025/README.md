# Login/security follow-up integration

Build15 stays at main `045169174188262f05b17c38495359e1059ea03b`. This draft combines only the exact tested blobs from PR1400/1401/1402/1403. No overlapping path exists and no implementation is re-created. The four original heads remain parents of this integration. No main, production Auth/provider/roles/Edge/gate, or user/business records are changed.

Changes: (1) pin Apple link preparation to the verified token and historical auth events; (2) reject invalid collector calendar/time evidence without rewriting valid strings; (3) keep new phone registration preparing until SMS readiness is explicitly released, retaining confirmed email/password and existing verified phone evidence; (4) invalidate pending operation proofs after session hops while accepting same-session JWT renewal.

Independent source checks passed. Run the existing focused remote workflows once against the combined tree; do not rerun unchanged build15 CI or local Flutter/Dart. Retarget/merge only after build15 is uploaded/installed and its preserved provenance no longer needs current main. Do not recreate or relabel build15 to contain these changes.

## Device checks kept distinct

Build15: retain current Google/Face ID/account/company; resume the saved checkout's correct date/report; actual reporter/supervisor signatures only; own worker facts/hours and registered allowances; authorized management recovery and approved edit; confirm the resulting authoritative attendance/payroll/report without synthesizing missing source evidence. Existing finalized documents and historical signatures stay fixed.

Follow-up release only: phone registration shows preparing and cannot send SMS or verify a code; confirmed email/password remains available; Apple preflight refuses changed sessions; valid same-account handoff still needs real provider/reauthentication/PKCE verification. Missing collector backend remains unavailable, not an empty-safe or attack-confirmed result. Full cross-company/API/Storage/actual device security proof remains outstanding.

Collector provisioning is a separate real blocker: the observed managed non-superuser's role-creation membership/catalog-lock contract is unresolved. The existing zero-artifact refusal is preserved. Do not solve it with SET/INHERIT grants, guessed privileges, removing locks, or fake events.
