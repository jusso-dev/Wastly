<p align="center">
  <img src="docs/banner.jpg" alt="Wastly: What they ate. What they left." width="100%" />
</p>

# Wastly

Private offline iOS diary of what a child eats and wastes.

Native SwiftUI. No account. Logs stay on the iPhone. iCloud backup is off in this build. The only planned network calls are food lookup (Open Food Facts, USDA) and an optional cheap LLM for fun facts.

App icon art: [docs/app-icon.svg](docs/app-icon.svg) and [docs/app-icon.jpg](docs/app-icon.jpg). The catalog slot points at that JPEG through a symlink. The file is 512 px, not a 1024 PNG.

Build prompt: [docs/BUILD.md](docs/BUILD.md)

## v1

- Eaten and wasted amounts on every log
- Local food store first, then Open Food Facts and USDA
- Fun facts from totals, not from body stats
- Face ID lock in the shell. No camera. Barcode is type plus Match.
- CloudKit backup is not on
- On-device Vision OCR is not on

Not a clinical dietitian. Not MyFitnessPal for adults.
