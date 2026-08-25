# Qiu

Qiu is a fast, lightweight and private offline selection translator for macOS.

Hold a configurable trigger key, select text in another application, and release the mouse. Qiu immediately opens a small popup near the cursor and translates the selection locally.

## Features

- Offline English → Chinese and Chinese → English translation
- Configurable keyboard, modifier-only, or mouse-button trigger
- Popup-first interaction with asynchronous selection reading
- Native macOS menu bar application built with Swift, AppKit and SwiftUI
- Lazy model loading, in-memory cache and explicit unload support
- No selected text sent to a remote inference service

OCR, cloud translation, browser extensions and general-purpose local LLMs are not currently supported.

## Requirements

- macOS 15 or later
- Apple Silicon for the currently verified release build
- Accessibility and Input Monitoring permissions for selection translation

Source builds additionally require Xcode Command Line Tools, CMake, Python 3 and SentencePiece. Homebrew users can install the native prerequisites with:

```bash
brew install cmake sentencepiece
```

## Usage

1. Launch Qiu and grant Accessibility and Input Monitoring access in System Settings.
2. Hold the configured trigger (Control + Option by default).
3. Select text with the mouse and release it.
4. Read the translation in the popup beside the cursor.

The trigger can be changed from Qiu Settings.

## Privacy

Translation inference runs locally. Selected text is not uploaded and Qiu does not keep translation history. Future language-pack downloads may use the network only after an explicit download action; translation text is not part of that traffic.

## Architecture

```text
Selection → Swift / AppKit → TranslationEngine → Objective-C++
          → SentencePiece → CTranslate2 → Accelerate + Ruy
```

The bundled OPUS-MT models are converted to CTranslate2 INT8 language packs. Model weights are release assets and are intentionally excluded from Git history.

## Build from source

Clone the repository with its pinned CTranslate2 dependency:

```bash
git clone --recurse-submodules https://github.com/Baijia-Yu/Qiu.git
cd Qiu
```

Build the native runtime, prepare the pinned model assets, test, and package the app:

```bash
./Tools/build_native.sh
./Tools/prepare_models.sh
swift test
./Tools/package_app.sh
```

`prepare_models.sh` downloads the two upstream Helsinki-NLP repositories and converts them locally. The downloads and generated weights are ignored by Git. Set `SENTENCEPIECE_PREFIX` if SentencePiece is installed outside the usual Apple Silicon or Intel Homebrew prefix.

The generated development app is `Distribution/Qiu.app`. It is ad-hoc signed for local testing; it is not notarized for public distribution.

## Models

Model provenance, pinned revisions and licensing are documented in [Models/README.md](Models/README.md). Third-party software and model notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Performance

The current memory attribution data and measurement notes are in [Benchmarks](Benchmarks/README.md). Performance results are hardware-specific.

## Roadmap

- Language-pack management UI
- Official downloadable language-pack catalogue
- Additional language pairs and lightweight automatic language detection
- Signed and notarized release packaging

## License

Qiu source code is available under the [MIT License](LICENSE). Third-party components and models remain under their respective licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
