# WastlyKit

Add the local Swift package to the Xcode app target.

```swift
import WastlyKit

let container = try WastlyContainer.make()
let store = LocalFoodStore(container: container)
await store.insertSeedIfEmpty()
let directory = LocalFirstFoodDirectory(
    store: store,
    live: RemoteFoodLookup(usdaAPIKey: "<key loaded from configuration>")
)
```

Energy is stored as kJ. Use `Energy.display(_:unit:)` for kJ/kcal labels.
Barcode match uses `Barcode.normalized` (leading zeros stripped).
The app target reads `USDA_API_KEY` from the optional, gitignored `Secrets.xcconfig`. Keep live keys out of source and fixtures.
