# Third-party notices

Qiu depends on third-party software and model data. This file is a summary; the corresponding upstream license text remains authoritative.

| Component | Use | License | Source |
| --- | --- | --- | --- |
| CTranslate2 | Native translation runtime | MIT | https://github.com/OpenNMT/CTranslate2 |
| SentencePiece | Tokenization | Apache-2.0 | https://github.com/google/sentencepiece |
| Ruy | INT8 matrix multiplication | Apache-2.0 | https://github.com/google/ruy |
| cpuinfo | CPU feature detection through Ruy | BSD-2-Clause | https://github.com/pytorch/cpuinfo |
| clog | Logging dependency through cpuinfo | BSD-2-Clause | https://github.com/pytorch/cpuinfo/tree/master/deps/clog |
| Helsinki-NLP OPUS-MT English → Chinese | Model data | Apache-2.0 | https://huggingface.co/Helsinki-NLP/opus-mt-en-zh |
| Helsinki-NLP OPUS-MT Chinese → English | Model data | CC-BY-4.0 | https://huggingface.co/Helsinki-NLP/opus-mt-zh-en |

The CTranslate2 source tree and its bundled dependency license files are available through the pinned `Vendor/CTranslate2` submodule. Binary releases must reproduce the notices required by these licenses. The Chinese → English model requires attribution under CC-BY-4.0; its Qiu package manifest records the upstream model and attribution.
