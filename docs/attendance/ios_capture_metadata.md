# Optional iOS capture metadata

`AttendanceCaptureMetadataService` exposes `readPhotoCapturedAt(localPhotoPath)` and
`reverseGeocodeCapturedLocation(latitude:, longitude:)` through the generated
AppDelegate's `sko.capture_metadata` channel. The coordinates must come from the
actual capture flow; neither API reads a site address or acquires a substitute GPS sample.

Photo metadata reads ImageIO EXIF DateTimeOriginal only with OffsetTimeOriginal.
Without a known offset it remains null. GPS DateStamp/TimeStamp may supply a UTC
instant. Camera-return time belongs in a separate observation field and must not
be substituted for this timestamp. Reads accept an existing absolute path inside
the iOS application container (after resolving symlinks), not a remote URL.

CLGeocoder resolves the supplied coordinates. The address remains null for missing
placemarks, network errors, or a five-second native timeout. Dart has a six-second
outer timeout. Enrichment failure must not block the original attendance/photo
flow. Non-iOS platforms explicitly return null; Android parity is not implemented.

The existing map channel, plugin registration, signing configuration, permission
strings, and iOS 15.5 target remain intact. No Supabase, authorization, or credential
changes are included. The generated Swift requires iOS CI compilation. No local
Flutter/Dart/Swift SDK is available here, and these tests have not run locally.
Physical iPhone capture metadata still requires Release-device verification.

Official Apple references:
- https://developer.apple.com/documentation/corelocation/clgeocoder
- https://developer.apple.com/documentation/imageio/kcgimagepropertyexifoffsettimeoriginal
- https://developer.apple.com/documentation/imageio/kcgimagepropertyexifdatetimeoriginal
- https://developer.apple.com/documentation/imageio/kcgimagepropertygpsdatestamp
- https://developer.apple.com/documentation/imageio/kcgimagepropertygpstimestamp

CLGeocoder is deprecated on newer SDKs in favor of MapKit APIs, but remains the
compatibility implementation for the project's iOS 15.5 minimum. A new SDK warning
must not be mistaken for actual device verification.
