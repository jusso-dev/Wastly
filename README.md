<p align="center">
  <img src="docs/banner.jpg" alt="Wastly: What they ate. What they left." width="100%" />
</p>

# Wastly

Private offline-first iOS diary of what a child eats and wastes.

Native SwiftUI. No account. Child logs stay on the iPhone. Energy is stored as kJ. Display can show kcal.

Food lookup is local first: recents, custom foods, a bundled seed catalog, then Open Food Facts and USDA results merged without duplicates. Copy `Secrets.xcconfig.example` to the gitignored `Secrets.xcconfig` for a USDA data.gov key. Open Food Facts barcode lookup works without one. NUTTAB is later, not v1.

Cloud plate matching is a separate, default-off opt-in. A configured HTTPS matcher receives only a compressed centre JPEG crop and returns candidates for parent confirmation; child details and source photo metadata are excluded.

Optional cheap LLM can turn totals into fun facts. It never gets body stats, photos, or date of birth.

Privacy and App Store disclosure notes: [docs/PRIVACY.md](docs/PRIVACY.md).

Wastly includes on-device Vision OCR, camera barcode scanning, Face ID lock, and optional private CloudKit backup. A parent can add a device-only password that encrypts the backup before upload; the password is never stored in iCloud and cannot be recovered. Backup runs when the app becomes active and can also be started or restored from Settings. Before distributing a build, create the `iCloud.au.yumait.Wastly` container for the signing team and deploy the `WastlyBackup` record schema to production in CloudKit Console.

App icon art: [docs/app-icon.svg](docs/app-icon.svg) and [docs/app-icon.jpg](docs/app-icon.jpg). The Xcode catalog uses `Wastly/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024 PNG).

How to use the kit: [Sources/WastlyKit/INTEGRATION.md](Sources/WastlyKit/INTEGRATION.md)

How to build: [docs/BUILD.md](docs/BUILD.md)

Not a clinical dietitian. Not MyFitnessPal for adults.
