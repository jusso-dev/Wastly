<p align="center">
  <img src="docs/banner.jpg" alt="Wastly: What they ate. What they left." width="100%" />
</p>

# Wastly

Private offline-first iOS diary of what a child eats and wastes.

Native SwiftUI. No account. Child logs stay on the iPhone. Energy is stored as kJ. Display can show kcal.

Food lookup is local first: recents, custom foods, 4,136 bundled offline foods, and an optional versioned bulk catalog, then Open Food Facts and USDA results merged without duplicates. The bundled catalogue includes every food profile in AUSNUT 2023 plus the additional profiles in AFCD Release 3. Bulk catalog packs download in the background and commit only when every pack succeeds, so the prior offline version survives a failed or cancelled update. Copy `Secrets.xcconfig.example` to the gitignored `Secrets.xcconfig` to set `CATALOG_URL` and an optional USDA data.gov key. Open Food Facts barcode lookup works without one. Sources, scope, generation, attribution, and licence: [docs/FOOD_DATA.md](docs/FOOD_DATA.md).

Cloud plate matching is a separate, default-off opt-in. A configured HTTPS matcher receives only a compressed centre JPEG crop and returns candidates for parent confirmation; child details and source photo metadata are excluded.

On iOS 26, an optional Apple Foundation Models path can turn deterministic totals into extra fun facts entirely on the device. It uses no endpoint or API key, checks Apple Intelligence and Australian-English availability, and falls back to the existing deterministic fact on unsupported devices or generation errors.

Privacy and App Store disclosure notes: [docs/PRIVACY.md](docs/PRIVACY.md).

Wastly includes on-device Vision OCR, camera barcode scanning, an optional Face ID or device-passcode diary lock, and optional private CloudKit backup. A parent can add a device-only password that encrypts the backup before upload; the password is never stored in iCloud and cannot be recovered. Backup runs when the app becomes active and can also be started from Settings. On an empty first launch, Wastly offers any available backup without importing it automatically; Settings also provides explicit merge-by-log-ID and replace choices. Before distributing a build, create the `iCloud.au.yumait.Wastly` container for the signing team and deploy the `WastlyBackup` record schema to production in CloudKit Console.

App icon art: [docs/app-icon.svg](docs/app-icon.svg) and [docs/app-icon.jpg](docs/app-icon.jpg). The Xcode catalog uses `Wastly/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024 PNG).

How to use the kit: [Sources/WastlyKit/INTEGRATION.md](Sources/WastlyKit/INTEGRATION.md)

How to build: [docs/BUILD.md](docs/BUILD.md)

Not a clinical dietitian. Not MyFitnessPal for adults.
