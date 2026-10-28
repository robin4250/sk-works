# One-attempt native HTTPS successor delivery (review-only, OFF)

`AppleSuccessorHttpsDelivery` supplies the previously missing native client
transport for a reviewed successor endpoint. Its immutable endpoint comes from
trusted application configuration, never from the enrollment response or a form.
It accepts only HTTPS without user-info/query/fragment, sends one POST with the
captured exact bearer, the existing password/id_token/nonce payload, and the
operation's `x-sko-request-id`. Redirect following is disabled, including 303.
There is no retry path, cookie cache, persistent credential cache or logging.

The original response must be 200, JSON/UTF-8, uncompressed, nonredirected and
explicitly `no-store`. The body is limited to 49,152 bytes even without a declared
length. Its exact seven-field envelope must match the captured request/actor.
One hard deadline covers connection, headers and body; expiry aborts the request
and force-closes its dedicated client. All errors are generic and terminate the
instance, so a lost response cannot cause a blind second link/exchange.

`AppleSuccessorClientPreparation.prepareFromHttps` binds this delivery to its
captured original application actor/bearer and then reuses the existing isolated
SDK getUser/identity/membership/session checks. The application Auth session is
never adopted, refreshed, replaced or persisted by this composition.

The transport is **not deployed or UI-connected**. The existing public handler
does not return this successor envelope, so pointing at it fails closed. A future
endpoint must authenticate and reserve the exact request ID before selecting the
existing TLS response sink; accepting an unverified request ID header is not a
reservation. Managed Auth/least-privilege endpoint composition, server request
limits, durable delivery/adoption acknowledgement and restart reconciliation,
global Auth-write serialization/CAS and the owner's iPhone flow remain required.
The SDK's silent ABA limitation remains. No production/provider/grant, account,
company, original signature/PDF or feature activation is changed.

Seventeen new Dart tests use a real loopback HTTPS server and an isolated synthetic
trusted CA (no bad-certificate callback). They cover OFF/config, one-use payload,
303 rejection, declared/chunked limits, foreign envelope/cache/encoding/UTF-8,
deadline/late result, generic errors and HTTPS -> isolated SDK composition with
the original application session unchanged. The existing five Node real-TLS sink
tests pass locally. Dart/Flutter is not installed locally; the new tests and
analysis are added to the existing dedicated CI and are pending its result.

Preparation invalidation now also cancels its owned active HTTPS delivery:
dispose, backgrounding and observed Auth-history changes abort the request and
force-close its dedicated client. A rejected overlapping preparation cannot
release the active delivery owner. Tests stall real TLS headers and bodies and
require cancellation to reject before server response release and the 20-second
deadline; pre-send cancellation makes no client. This is local cancellation only,
not proof that already-received server work was rolled back. The outcome remains
unknown and the original one-attempt delivery cannot be reused.

The first CI passed analysis and 29 cases; its single composition-fixture failure
was hidden by the production generic error boundary. The followup keeps the real
SDK Auth stream in that success case and adds safe path/event-type/boolean stage
diagnostics rather than guessing a cause. Cancellation cases use explicit Auth
history fixtures to control their invalidation event. New CI must pass before
claiming this composition is verified.

Primary references: [Dart HTTPS/certificate handling](https://api.dart.dev/dart-io/HttpClient-class.html),
[redirect policy](https://api.dart.dev/dart-io/HttpClientRequest/followRedirects.html),
[force-close behavior](https://api.dart.dev/dart-io/HttpClient/close.html).
