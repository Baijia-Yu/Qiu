# 产品与技术决策（MVP）

## 已确认的体验

1. 默认按住 `Control + Option` 后划词；松开鼠标即触发。
2. Popup 必须先显示加载状态，后异步读取选区并翻译；不等待推理结果再创建窗口。
3. 弹窗默认位于鼠标右下方；若越过当前屏幕可视边界，自动翻到上方并横向夹紧。
4. 只做英⇄中、文本划词与离线翻译。OCR、历史记录、云同步、多语言不进入 MVP。
5. 无选区、空闲时不做轮询、不加载模型、不发出网络请求。

## 模型决策

| 选项 | 结论 | 原因 |
| --- | --- | --- |
| OPUS-MT（Marian）双向 | **MVP 默认** | 专用机器翻译模型，适合短句，体积和延迟远低于通用 LLM。 |
| CTranslate2 INT8 | **MVP 运行时** | 原生 C++ 推理、支持 OPUS-MT/INT8，适合 ARM64 与 x86-64。 |
| NLLB 600M | 不作为默认 | 多语言能力更强，但不符合本产品“中英优先、轻量”的资源目标。 |
| 0.5B–1.5B LLM | 不作为默认 | 对短文本翻译的收益不足以抵消内存、冷启动与功耗。 |

发布版将两套已转换模型作为只读 Qiu Language Pack 存放在 `Qiu.app/Contents/Resources/LanguagePacks/`：`opus-mt-en-zh-int8/1.0.0` 与 `opus-mt-zh-en-int8/1.0.0`。每个包都有 `qiu-package.json`、CTranslate2 模型和 SentencePiece 分词器；App Bundle 不会被下载、导入或更新操作修改。原始权重保留在 `Models/source`，便于可复现转换。模型来源为 Helsinki-NLP；英→中为 Apache-2.0，中→英为 CC-BY-4.0，发布包必须保留各自归属信息。

## 正式版工程边界

Swift/AppKit 负责菜单栏、权限、选区、Popup、缓存与设置。CTranslate2 C++ 负责模型加载和推理；SentencePiece 负责分词。桥接层位于 `Sources/CTranslateBridge/CTranslateBridge.mm`，对 Transformers-converted Marian 明确追加 `</s>`，已和 Python 参考路径对齐。Swift 只通过一个 `TranslationEngine` 接口调用桥接层，因此切换为 Core ML 或另一套 NMT 模型时不会改 UI。

## 验收指标

- Popup：鼠标松开后立即显示加载卡片，目标 < 50 ms。
- 缓存命中：< 10 ms。
- Warm 短句：Apple Silicon 目标 < 300 ms；Intel CPU 目标 < 1 s。
- 空闲：没有模型推理、没有网络请求、没有轮询。

最终指标必须在目标机型上以 1、5、10、20、50、100 词样本测量 P50/P95 后确认，不能用模型宣传参数代替实际测量。
