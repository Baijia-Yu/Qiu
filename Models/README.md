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

The English → Chinese and Chinese → English models have different licenses. Qiu application licensing does not replace or override either model license. Distributions must retain the model source, license and attribution recorded in each package manifest and in `THIRD_PARTY_NOTICES.md`.
