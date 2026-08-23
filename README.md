<p align="center">
  <img src="docs/banner.jpg" alt="Wastly: What they ate. What they left." width="100%" />
</p>

# Wastly

Private offline-first iOS diary of what a child eats and wastes.

Native SwiftUI. No account. Child logs stay on the iPhone. Energy is stored as kJ. Display can show kcal.

Food lookup is local first: recents, custom foods, a bundled seed catalog, then a versioned catalog pull when a host is set. On a miss it can call Open Food Facts and USDA. Put the USDA key in Secrets.xcconfig, not git. NUTTAB is later, not v1.

Optional cheap LLM can turn totals into fun facts. It never gets body stats, photos, or date of birth.

This cut is the Swift package `WastlyKit`. The app shell is a stacked pull request. Vision OCR, CloudKit, and a live catalog host are not wired yet. Backup code exists as an envelope (wrong password does not change the store).

App icon art: [docs/app-icon.svg](docs/app-icon.svg)

How to use the kit: [Sources/WastlyKit/INTEGRATION.md](Sources/WastlyKit/INTEGRATION.md)

How to build: [docs/BUILD.md](docs/BUILD.md)

Not a clinical dietitian. Not MyFitnessPal for adults.
