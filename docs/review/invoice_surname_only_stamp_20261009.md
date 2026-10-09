# Invoice surname-only personal seals

Only the invoice PDF display changes. Approved seals contain the surname alone, with no role/date bands. IDs, full names, approval state, actual timestamps, display-date metadata and history remain unchanged. Payroll, payment certificates and company seals are outside this change.

The existing source provides one `user_profiles.display_name` string, not a separate surname field. Names separated by an ASCII/full-width space use the first component. Joined names such as `斉藤隆一` are not split by guessed Japanese name boundaries and are not rendered as a full name in a surname-only seal. Their circle remains, but its name is blank. An explicit surname registration contract remains unfinished; this draft must not be described as complete for joined-name users.

Actual Flutter PDF tests cover approved/pending stamps, separated names, joined names, timestamp/ID retention and amount/A4 preservation. Local Flutter is unavailable: validation must use CI artifacts. No DB/Auth/RLS changes or production application.
