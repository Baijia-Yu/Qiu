# Qiu language-pack models

Model weights are not stored in Git. `Tools/prepare_models.sh` downloads pinned upstream revisions and creates the following Qiu language packs:

| Package | Upstream model | Pinned revision | Model license |
| --- | --- | --- | --- |
| `opus-mt-en-zh-int8@1.0.0` | `Helsinki-NLP/opus-mt-en-zh` | `408d9bc410a388e1d9aef112a2daba955b945255` | Apache-2.0 |
| `opus-mt-zh-en-int8@1.0.0` | `Helsinki-NLP/opus-mt-zh-en` | `cf109095479db38d6df799875e34039d4938aaa6` | CC-BY-4.0 |

Each package contains:

```text
qiu-package.json
ct2/model/                 # CTranslate2 INT8 conversion
sentencepiece/source.spm
sentencepiece/target.spm
```

The package manifests are version-controlled. Downloaded source weights, converted model binaries and tokenizer files are ignored. Conversion uses the pinned Python dependencies in `Tools/model-requirements.txt` and `ct2-transformers-converter --quantization int8`.

## Official download catalogue

[`catalog-v1.json`](catalog-v1.json) is the machine-readable catalogue used by Qiu's Settings window. Catalogue access is user-initiated; the app does not fetch it at launch or while idle. Each entry declares:

```text
packageID + version
sourceLanguage + targetLanguage
downloadURL (HTTPS only)
sizeBytes
sha256
license
```

Official archives use the `.qiu-languagepack` extension and are ZIP files containing the layout above. Before installation, Qiu verifies the declared byte size and SHA-256, validates the internal manifest and required files, checks that the downloaded package identity matches the catalogue entry, and moves it into Application Support atomically. A downloaded package is never loaded merely because it was installed; users can select it per direction in Settings.

The English → Chinese and Chinese → English models have different licenses. Qiu application licensing does not replace or override either model license. Distributions must retain the model source, license and attribution recorded in each package manifest and in `THIRD_PARTY_NOTICES.md`.

## User-provided MLX models

On Apple Silicon, Advanced Model Management can reference a local MLX model directory. Qiu does not copy the directory into Application Support. It stores a macOS security-scoped bookmark, loads the model only when selected or explicitly preloaded, and removes only that reference when the user chooses **Remove Reference**.

The selected directory must use the normal MLX / Hugging Face layout:

```text
My-MLX-Model/
├── config.json
├── tokenizer.json             # or tokenizer_config.json
├── tokenizer_config.json      # commonly included
├── model.safetensors          # or sharded *.safetensors files
└── model.safetensors.index.json  # optional for sharded weights
```

The architecture named by `config.json` must be supported by the pinned `mlx-swift-lm` release. Quantized MLX Community conversions are recommended for lower memory use. Qiu displays the weight size and a conservative memory estimate before loading; actual unified-memory use depends on model architecture, quantization, input length, and generated output. Users remain responsible for each imported model's license and terms.
