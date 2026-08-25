# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and intends to use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Documented Qiu's custom hold-and-select trigger, automatic EN/ZH direction detection, current language-pack backend, and planned model deployment capabilities.

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
