# Wastly build

Open `Wastly.xcodeproj` and add the local Swift package at the repo root (`WastlyKit`). iOS 18+. Swift 6.

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

Energy is kJ in the store. Use `Energy.display` for kJ/kcal labels. Barcodes strip leading zeros.

For USDA, copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and replace the placeholder. The project includes this file when present, and git ignores it. Never put a live key in tracked source.

Optional plate matching uses `PLATE_MATCH_URL` and `PLATE_MATCH_API_KEY` in the same gitignored file. The HTTPS endpoint accepts `{"image":"<base64 JPEG>","mimeType":"image/jpeg"}` and returns `{"candidates":[{"id":"...","name":"...","confidence":0.0,"kilojoulesPer100g":0.0,"servingGrams":0.0}]}`. Energy and serving fields are optional. The app never calls it until the parent enables the Settings toggle and chooses a photo.

Tabs: Today, Diary, Facts, Kids, Settings. The log sheet supports search, typed barcode matching, and camera scanning. App Icon is `AppIcon.png` in the asset catalog (1024 PNG).

Do not give medical advice, BMI lectures, or healthy-weight scores.

The full product rules live in the GitHub issues. This file is the build map, not a second spec.
