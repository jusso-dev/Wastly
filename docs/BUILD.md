# Wastly build

Open the Xcode project on this branch and add the local Swift package at the repo root (`WastlyKit`). iOS 18+. Swift 6.

```swift
import WastlyKit

let container = try WastlyContainer.make()
let store = LocalFoodStore(container: container)
await store.insertSeedIfEmpty()
let directory = LocalFirstFoodDirectory(
    store: store,
    live: RemoteFoodLookup(usdaAPIKey: nil)
)
```

Energy is kJ in the store. Use `Energy.display` for kJ/kcal labels. Barcodes strip leading zeros.

Put the USDA key in Secrets.xcconfig. That file is gitignored.

Tabs on this branch: Today, Diary, Facts, Kids, Settings. The log sheet search is wired. Barcode is a typed field plus Match, not a live camera. App Icon is `AppIcon.png` in the asset catalog (1024 PNG).

Do not give medical advice, BMI lectures, or healthy-weight scores.

The full product rules live in the GitHub issues. This file is the build map, not a second spec.
