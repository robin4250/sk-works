# Individual payroll action ownership

The individual payroll screen always supplies its fixed action footer. The embedded unit editor previously also supplied actions on the monthly view whenever monthly unit items existed, and after a failed unit load. This produced two Add/Register pairs. The host now owns the footer for all units; the existing monthly `_save` path and unit draft preparation are unchanged.

The unit-load error still disables adding a new hour/day condition when its storage version is unavailable. Existing worker allowance rows retain their existing save path. No errors are ignored, no permissions are broadened, and no payroll amounts, RPCs, schema, company/person checks or production records are modified. No worker name or ID is special-cased.

The fixed-footer suite adds monthly success/failure cases with and without monthly unit items, plus a same-session employee switch through a failed load and retry recovery. The existing dedicated workflow runs analysis and payroll UI/contract tests on this branch. CI results are pending; physical device delivery/verification is not performed.

A production user-specific load failure remains a separate investigation. An administrator query without the user's auth context is not evidence of that user's runtime error.
