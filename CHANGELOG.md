# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Added per-direction selection of installed language packs in Settings, with persistent preferences, automatic newest-version fallback, and model-list refresh.

### Changed

- Documented the planned on-device translation personalization roadmap and its user-controlled privacy boundaries.

## [0.1.0-alpha.3] - 2026-08-26

### Fixed

- Apply Accessibility and Input Monitoring permission changes without requiring Qiu to restart.
- Preserve mathematical symbols, Greek letters, superscripts, emoji, and other tokenizer-unknown Unicode characters in offline translation results.
- Avoid rejecting an entire offline translation just because the selected text contains a character outside the OPUS-MT tokenizer vocabulary.
- Prevent internal placeholder text from leaking into translations of academic notation.
- Restore NFKC-normalized mathematical glyphs with model attention and retain unaligned symbols in a deterministic fallback line.

### Changed

- Detect and sanitize source-side unknown spans with SentencePiece byte offsets before inference.
- Use CTranslate2's native attention-based unknown replacement instead of model-facing text placeholders.
- Document Unicode preservation in the Chinese and English feature lists.

### Added

- Added English → Chinese and Chinese → English regression coverage using `μ`, `∈`, `²`, `≤`, `Δ`, `≈`, and emoji.
- Added an academic-notation regression using `𝓜`, `𝓘`, `Ψ`, `Ω`, `⟨⟩`, and `⋯`.

## [0.1.0-alpha.2] - 2026-08-26

### Changed

- Documented Qiu's custom hold-and-select trigger, automatic EN/ZH direction detection, current language-pack backend, and planned model deployment capabilities.
- Added distinct prerelease artifact naming and incremented the app build number to 2.

## [0.1.0-alpha.1] - 2026-08-26

### Added

- Qiu language-pack manifest validation, discovery, routing and local import foundation.
- Standard read-only bundled English ↔ Chinese language packs.
- Reproducible Developer ID signing, DMG creation and Apple notarization workflow.
- Privacy-safe application identifier and public Git author metadata.
- Bilingual project README with origin story, benchmark visualization, usage guide, and roadmap.
- Native macOS menu bar application.
- Configurable selection trigger and permission status UI.
- Popup-first selection translation.
- Offline English ↔ Chinese OPUS-MT translation.
- Objective-C++ bridge with SentencePiece and CTranslate2.
- Accelerate FP32 operations and Ruy INT8 GEMM.
- Lazy loading, unload/reload, LRU cache and latency metrics.
- Native stability and memory-attribution tests.
