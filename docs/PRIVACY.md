# Privacy boundaries

Wastly has no account, ads, analytics SDK, or tracking. Child profiles and diary rows stay in the local SwiftData store unless a parent enables private iCloud backup.

## Network destinations

- Food lookup: HTTPS requests only to `world.openfoodfacts.org`, `world.openfoodfacts.net`, `api.nal.usda.gov`, and `fdc.nal.usda.gov`.
- Bulk catalog: HTTPS only. A deployment must explicitly add its catalog host to the code-level allowlist.
- Plate matching: disabled by default and unconfigured in a default build. When the parent opts in and chooses a photo, Wastly sends only a metadata-stripped, compressed centre JPEG crop plus its MIME type to the explicitly configured HTTPS host. Child names, IDs, body data, diary notes, and original EXIF/GPS metadata are excluded.

## On-device AI

Optional fun facts are disabled by default. On iOS 26, Apple’s Foundation Models framework processes a deterministic statement containing diary totals, top food, and an optional first name entirely on the device. Wastly has no fact-service endpoint or API key, and unsupported or unavailable models fall back to deterministic facts. Date of birth, age, measurements, full child profiles, and photos are never included in the model prompt.

App Transport Security remains at its secure defaults; Wastly declares no arbitrary-load exception. Runtime diagnostics must use Apple unified logging and must not log child fields or request bodies.

## App Store privacy answers

Draft answers for App Store Connect, to re-check against the release build:

- Data used to track: none.
- Data linked to identity: none; Wastly has no account or advertising identifier.
- Data collected by the developer: none for the default offline experience.
- User content in private iCloud backup is stored in the parent’s private iCloud container when explicitly enabled.
- Private backup contains child profiles and photos, measurements, diary logs, custom foods, and app settings. Downloaded provider/catalog food data is excluded. Wastly stores one versioned envelope in the parent’s private CloudKit database and never sends it to a Wastly server.
- Optional backup passwords stay in the device-only, non-synchronising Keychain. Password-protected envelopes use PBKDF2-HMAC-SHA256 and AES-GCM before upload; iCloud receives only the encrypted envelope and its encryption metadata, never the password.
- A forgotten backup password cannot be recovered and makes that encrypted iCloud backup unusable. Existing local data remains available and unchanged.
- Optional diary locking uses Apple LocalAuthentication. Wastly receives only an authentication result; it never receives or stores Face ID, Touch ID, or device-passcode data.
- Food search terms go to the selected food provider to return lookup results; they contain no child profile fields.

Before release, repeat a Charles or Proxyman pass on a physical device for food search, barcode lookup, catalog sync, and optional plate matching. Enable on-device facts during the pass and confirm they emit no network request. Confirm every actual destination and inspect request bodies for forbidden child fields.
