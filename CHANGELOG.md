# Changelog

## [Unreleased]

- Scaffold the project: Swift Package Manager layout, signing and notarization
  wiring, bilingual README, and the RFP in both languages.
- Add the pure model layer — spacing keys, absent-aware stored values, minimal
  write plans, the four presets, and the restore decision that refuses to
  overwrite an external change or write from a corrupt backup — with 19 tests.
- Add a read-only preference reader for the current-host and any-host scopes,
  and a window shell that describes the live state. Nothing is written yet.
