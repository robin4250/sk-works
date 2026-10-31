# RAM-first input route (source candidate only)

`SiteOrderOutgoingEntryPage` preserves this order: unbound RAM input, explicit
input confirmation, registered-company dropdown, actual `outgoingContext`
verification, site body factory binding, formal PDF review, price/unit/recipient
confirmation. No invented company identifier or zero unit price is used.

The company selector takes verified registered directory IDs and display names
from its caller. It does not reuse `TradeCompanyRepository.loadAll`, which first
calls a directory synchronization writer. The hosted read-only directory loader
is still a dependency. Selection is not authority: the existing outgoing context
must confirm the selected company's formal link, current actor/session, role,
source and own seal before rendering. Final confirmation displays the freshly
bound canonical recipient name rather than a potentially stale directory label.

Returning from company selection or final confirmation retains input. The
existing `TradeDocumentTouchEditorPage` is reused for paper editing after binding;
its editable fields survive a return to the first input step and a fresh source
binding. Company identity, terms, registered parties and seal are never copied
into that editable patch. Scope or visibility retirement destroys all RAM input
and preview bytes. Numeric input has a Done action and outside-tap dismissal.

The route returns a RAM-only `SiteOrderReviewedInput`; it does not prepare, sign,
register, send, or imply that a reviewed local PDF is a server original. There is
no application/main entry and no share/send button until the dedicated guarded
writer is connected. The future writer must durably save request IDs before
HTTP, reconcile unknown outcomes, fetch and re-render the server's canonical
body, and obtain fresh explicit consent under the unsigned-operation barrier.
An advanced prepare is not a terminal sent receipt and cannot clear quarantine.

Remaining: real read-only target loader, guarded preview/consent wrapper and
its exact dependency/catalog seal, canonical original/PDF/storage/send, terminal
receipt reconciliation, feature approval/deployment and physical iPhone checks.
Existing shared Draft/Session/Auth and financial RPCs remain unchanged.
