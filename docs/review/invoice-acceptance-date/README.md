# Monthly invoice acceptance initial date

For an unsaved monthly invoice appendix, the acceptance date is the last day of the month before the target month (October 2026 → September 30, 2026). The order date stays the previous month’s fifteenth. The parent invoice issue date is not an acceptance-date source.

Both the initial editor and automatic PDF resolver discard only the copied parent issue date before using the shared initial-default function. Explicit draft dates passed to that function and saved attachments retain their exact values. Editor explicit input remains after defaults. No save, approval timestamp, source revision protection, original, signature, standalone document, Auth, or database behavior changes.

Validation is performed by the focused R18/resolver tests and existing actual PDF workflows. PDF extraction checks the automatic acceptance page’s September 30 date while retaining saved acceptance dates and identical parent-page pixels/text. Local Flutter execution is unavailable; CI outcomes must be checked separately.
