# SKO backup / restore contract

This contract protects production recovery work.

- Recovery baseline branch: `backup/pre-restore-20261002-0532`.
- Recovery baseline main SHA: `b230b4b578c02642fd3911472a13288eabdbccde`.
- Recovery integration branch: `restore/ui-specs-20261002`.
- Never rewrite or delete the recovery baseline branch during restore work.
- Production Supabase changes are forward-only migrations. Do not use database reset,
  destructive schema recreation, or migration history rewriting as a recovery shortcut.
- A migration applied to production must remain represented by the matching migration
  file in GitHub.
- Before device release, run `tool/pre_device_release_gate.sh` and the normal
  Flutter CI, iOS CI, and Secret Scan.
- A restore is not complete until a Release build is installed on the target iPhone
  and the requested device-review route has been checked.
- If a restore slice causes a regression, revert that slice or apply a forward fix;
  do not erase unrelated production data.
- User-specific appearance settings and chat/home backgrounds are local/personal
  preferences and must not be restored into another user's settings.
