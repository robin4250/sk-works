# Frozen nonfinancial received site snapshot

Review-only bootstrap candidate. No existing production package/table is changed;
this feature has not been installed and remains default OFF / production HOLD.

The original send transaction now stores its sanitized nonfinancial site
projection inside the immutable package row as well as the legacy transport item.
Approval reads the package snapshot. A later legacy transport edit cannot change
the site name/address that the recipient approved or introduce financial notes.
The accepted public site still receives only the explicit nonfinancial columns.

Exact source guards are advanced for the changed send/approve bodies. The global
legacy approval body, consent guards, management permissions and original PDF
records remain unchanged. A regression modifies the legacy item after receipt,
then checks that approval uses the original frozen name/address and no notes.

This does not merge deliberately distinct packages into one construction site or
provide cross-session uncertain-operation recovery. Those remain separate work.
