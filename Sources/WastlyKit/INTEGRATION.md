# WastlyKit

Add the local Swift package to the Xcode app target.

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

Energy is stored as kJ. Use `Energy.display(_:unit:)` for kJ/kcal labels.
Barcode match uses `Barcode.normalized` (leading zeros stripped).
USDA key goes in Secrets.xcconfig, not git.
