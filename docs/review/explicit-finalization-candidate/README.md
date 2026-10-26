# Explicit final save — work in progress

Base: 112b989978b2f784e66854d12315fec649ecbadf. REVIEW ONLY, DEFAULT OFF, NOT NATIVE VERIFIED, NOT DEPLOYED.

The current ordinary v2 contract materializes confirmed facts and creates financial sources during supervisor signature capture. This candidate separates evidence capture from the final explicit save. Reporter capture provisionally saves the actual category/allowances/hours confirmation without inferring missing values. Supervisor capture stores actual evidence. Only finalize_shared_daily_report validates current actual receipts, whole-roster facts, source and CAS, then invokes the original financial writers atomically.

The candidate keeps exact source pins and original definitions. The ordinary raw writer retains an existing work category when an older payload omits it; no NULL-to-day inference is added. start_shared_report_finalization_edit preserves actual old signatures and facts in audit history, clears both current signatures and requires new actual capture before finalization. A used enrollment is sticky: disabling rollout cannot fall through to the old implicit finalization path.

Current implementation is a checkpoint, not a verified delivery. Remaining work: exact-source Native installation, actual payroll/invoice producer closure and missing/protected output rollback, current source/permission races, approved edits/deletions, independent route-visit document save/finalize and unused restoration. No production write, main integration, local Flutter or local Dart execution is authorized here.

prepare_candidate.py is an offline assembler using the checked-in technical source originals. It does not connect to a database. core.sql is assembled with source-bound replacements into explicit-finalization.sql.review-only.
