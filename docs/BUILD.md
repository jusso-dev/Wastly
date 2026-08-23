# Wastly build

Open `Wastly.xcodeproj` and add the local Swift package at the repo root (`WastlyKit`). iOS 18+. Swift 6.

```swift
import WastlyKit

let container = try WastlyContainer.make()
let store = LocalFoodStore(container: container)
try await store.insertSeedIfEmpty()
let directory = LocalFirstFoodDirectory(
    store: store,
    live: RemoteFoodLookup(usdaAPIKey: "<key loaded from configuration>")
)
```

Energy is kJ in the store. Use `Energy.display` for kJ/kcal labels. Barcodes strip leading zeros.

For USDA, copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and replace the placeholder. The project includes this file when present, and git ignores it. Never put a live key in tracked source.

Set `CATALOG_URL` to an HTTPS dump endpoint to enable background bulk catalog updates. Wastly sends only `updatedSince=<version>` and `pack=<number>`, plus `If-None-Match` when it has an ETag. Each response is `{"version":2,"etag":"...","pack":1,"totalPacks":2,"foods":[...]}` using the `SeedFood` field names. All packs must share a version; Wastly commits them together only after the final pack succeeds. Defaults cap a pack at 8 MiB, one update at 64 MiB/100 packs, and the local catalog at 100,000 rows. The endpoint receives no child, diary, photo, or account data.

Optional plate matching uses `PLATE_MATCH_URL` and `PLATE_MATCH_API_KEY` in the same gitignored file. The HTTPS endpoint accepts `{"image":"<base64 JPEG>","mimeType":"image/jpeg"}` and returns `{"candidates":[{"id":"...","name":"...","confidence":0.0,"kilojoulesPer100g":0.0,"servingGrams":0.0}]}`. Energy and serving fields are optional. The app never calls it until the parent enables the Settings toggle and chooses a photo.

Optional online facts use `FACT_SERVICE_URL` and `FACT_SERVICE_API_KEY` in `Secrets.xcconfig`. The explicitly configured HTTPS endpoint receives only `first_name` (when provided), `days`, `eaten_g`, `wasted_g`, and `top_food`. It returns one to three neutral facts plus arithmetic working as `{"facts":["..."],"debug":"500 g / 500 g per footy = 1 footy"}`. The `X-Wastly-Fact-Prompt: neutral-v1` header selects the prompt contract; failures and non-2xx responses leave the offline template in place.

Tabs: Today, Diary, Facts, Kids, Settings. The log sheet supports search, typed barcode matching, and camera scanning. App Icon is `AppIcon.png` in the asset catalog (1024 PNG).

Do not give medical advice, BMI lectures, or healthy-weight scores.

The full product rules live in the GitHub issues. This file is the build map, not a second spec.
