# Offline site-order production-input inventory

This tool prepares review information only. It has no SQL executor, network client,
subprocess launcher, installer, feature activation, invitation or send operation.
Every result retains `deployable:false` and `capture_qualified:false`. A successful
exit means the fixed source inputs matched, never that production is ready.

The source inventory is pinned from #1707 `bfc53de7a374b39785d27cea77710ce1088535e3`
(`combined-source-contract.json`) and #1700
`1bcc8150cc4614f1f91ec2484495d3e3f0d89c7b` (`source-inventory.json`).
The fifteen existing relation names are the union of the nine-name baseline
manifest and six-name full-existing-contract at
`14cf77f4b166bcb86d0f5fef68080841ac89a27a`. Old captures, fixture schemas and
published declarations are not current full production metadata.

The inventory contains 22 SQL source units, nine fixed execution sources and eight
canonical Edge/Wasm builder inputs. Renderer inputs use their actual repository
directory `tool/canonical_edge_wasm`, not the application renderer directory.
The canonical builder manifest still requires its own 25 source/six asset closure;
the four generated output pins and complete hosted CLI bundle remain separate.
No inventory array is an execution order and SQL transaction text is not joined.

The confirmation API source is inspected as a pinned input, with mode
`actor_only`: only the existing separately pinned private actor extraction is in
the review plan. This tool does not emit that actor or authorize installing the
financial API bundle. The superseding #1703 compatibility source replaces the
older same-named proposal. Including both, substituting fixture helpers or adding
unknown sources is rejected. Immutable C capsule SHA256 remains
`0c1a57402c666e991001814af5cdaa0f5bde138bf05e533c3e375bffb2d0e8f4`;
this tool neither edits nor emits it.

Duplicate JSON keys, nonfinite numbers, unknown fields, duplicate source units,
unsafe paths, symlinks, byte/hash drift, wrong commits and full financial bundle
selection fail closed. The bounded-file and strict JSON principles reuse #1718's
offline qualifier contract; they do not import deployment authority from its
expected13 disposable runtime receipt.

## Input and output boundaries

`manifest.schema.json` describes the manifest. Each source entry identifies its
fixed commit/path/mode and a local regular-file reference containing its SHA256.
Each of the four capture groups is mandatory as a field and may be `null` when
missing. Null produces an explicit missing item, not an empty successful capture.

No current capture receipt is independently registered in this candidate. Any
non-null capture therefore refuses qualification, even if its self-reported hash
matches or it claims `native:true`. This is intentional: source reconstruction
cannot manufacture the actual fifteen-table contract, all function overloads,
namespace/default ACL state, or complete callers/Edge SQL dependencies.
Declared function names in the output are not complete callable signatures or a
SQL parser. Static/dynamic/external caller closure remains unresolved.

Registering a future actual capture requires a separately reviewed source change
defining its exact typed record contract, independently verified producer/receipt,
full relation/function identities, owner/ACL/RLS/defaults/constraints/indexes/
triggers/policies and current capture provenance. Merely appending a digest to the
empty registry is insufficient. The current implementation has no acceptance
path for such captures and makes no production-readiness claim.

Operational evidence is currently `null` only. A caller-authored boolean is not an
admission-controller acknowledgement. Real maintenance ownership, all ingress
coverage, a held closure, accepted-work reconciliation and old-frame drain are
unproved. Public ACL revocation alone has already failed to establish closure in
#1729; C commit alone failed to drain an entered predecessor in #1726. Orders OFF
does not stop all ordinary saver entry points. No new production query or stop
command is supplied here. Production HOLD remains, and individual exemptions / A
/ B retain their separately approved states.

Run source-only checks:

```
python3 -m unittest discover -s tool/site_order_production_inputs -v
python3 tool/site_order_production_inputs/qualify.py --input-root /private/input-directory
```

Tests use explicit synthetic pins only to check parser outcomes. They are not
current catalog, real Auth, Storage, hosted Edge, partner, iPhone or execution
evidence. Main integration, separate production approval, activation and actual
sender/recipient/device checks remain outside this candidate.
