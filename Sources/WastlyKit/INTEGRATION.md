# WastlyKit

Add the local Swift package to the Xcode app target.

```swift
import WastlyKit

let container = try WastlyContainer.make()
let store = LocalFoodStore(container: container)
try await store.insertSeedIfEmpty()
let directory = LocalFirstFoodDirectory(
    store: store,
    live: RemoteFoodLookup(usdaAPIKey: "<key loaded from configuration>")
)

let catalogSync = CatalogSync(
    store: store,
    extraHosts: ["catalog.example"]
)
try await catalogSync.pull(from: URL(string: "https://catalog.example/v1/foods")!)
```

Energy is stored as kJ. Use `Energy.display(_:unit:)` for kJ/kcal labels.
Barcode match uses `Barcode.normalized` (leading zeros stripped).
The app target reads `CATALOG_URL` and `USDA_API_KEY` from the optional, gitignored `Secrets.xcconfig`. Catalog requests are GET-only and contain `updatedSince` plus `pack`; responses use the `CatalogPack` JSON contract. Each food needs either a real numeric `barcode` or a stable namespaced `catalogID`; generic foods use an empty barcode so they cannot match a scanner result. Default limits are 8 MiB per pack, 64 MiB/100 packs per update, and 100,000 stored rows. Keep live keys out of source and fixtures.
Optional plate matching reads `PLATE_MATCH_URL` and `PLATE_MATCH_API_KEY` from that file. It is default-off and only sends the output of `PlateImagePreparer.jpegCrop` after explicit user action.
