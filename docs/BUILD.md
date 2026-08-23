# Wastly — native Swift iOS build prompt

Build **Wastly**, a native SwiftUI iOS app. One job: a parent keeps a private diary of how much their child **eats** and how much they **waste**. It is offline-first. The only network calls are food lookup (search, barcode, optional photo OCR match) and a cheap LLM that turns totals into fun facts. Child name, age, weight, height, logs, and photos never leave the device except as an iCloud backup the parent controls.

This is not MyFitnessPal for adults. It is not a clinical dietitian. Do not give medical advice, BMI lectures, or healthy-weight scores.

Reference the Lifesum iOS Tracking food intake flow on Mobbin (https://mobbin.com/explore/flows/3a8645fc-a11d-4896-9727-009752197d2b) and the Lifesum Tracking a meal flow (https://mobbin.com/explore/flows/448ee6dd-7e6c-401c-bce1-c26ed999f387). Steal the structure, not the brand. Keep Wastly calmer and more journal-like than a gym tracker.

Full product rules, data model, lookup, facts, screens, and acceptance are in this file as filed in the original prompt. Follow the GitHub issues on this repo for the build order.