# Privacy boundaries

Wastly has no account, ads, analytics SDK, or tracking. Child profiles and diary rows stay in the local SwiftData store unless a parent enables private iCloud backup.

## Network destinations

- Food lookup: HTTPS requests only to `world.openfoodfacts.org`, `world.openfoodfacts.net`, `api.nal.usda.gov`, and `fdc.nal.usda.gov`.
- Bulk catalog: HTTPS only. A deployment must explicitly add its catalog host to the code-level allowlist.
- Fun facts: disabled by default. A deployment must explicitly configure one HTTPS LLM host. Payloads contain aggregate days, eaten grams, wasted grams, top food, and optional first name only.
- Plate matching: disabled by default and unconfigured in a default build. When the parent opts in and chooses a photo, Wastly sends only a metadata-stripped, compressed centre JPEG crop plus its MIME type to the explicitly configured HTTPS host. Child names, IDs, body data, diary notes, and original EXIF/GPS metadata are excluded.

Date of birth, age, measurements, full child profile, and profile photos are forbidden in fun-fact payloads. `PrivacyGuard` rejects forbidden keys, including nested keys, before a request can be sent.

App Transport Security remains at its secure defaults; Wastly declares no arbitrary-load exception. Runtime diagnostics must use Apple unified logging and must not log child fields or request bodies.

## App Store privacy answers

Draft answers for App Store Connect, to re-check against the release build:

- Data used to track: none.
- Data linked to identity: none; Wastly has no account or advertising identifier.
- Data collected by the developer: none for the default offline experience.
- User content in private iCloud backup is stored in the parent’s private iCloud container when explicitly enabled.
- Private backup contains child profiles and photos, measurements, diary logs, custom foods, and app settings. Downloaded provider/catalog food data is excluded. Wastly stores one versioned envelope in the parent’s private CloudKit database and never sends it to a Wastly server.
- Food search terms go to the selected food provider to return lookup results; they contain no child profile fields.

Before release, repeat a Charles or Proxyman pass on a physical device for food search, barcode lookup, catalog sync, optional facts, and optional plate matching. Confirm every destination and inspect bodies for forbidden child fields.
