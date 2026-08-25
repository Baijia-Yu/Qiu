# Benchmarks

`native-memory-benchmark.csv` records the native runtime memory-attribution run used for the current baseline.

- Machine: MacBook Pro with Apple M4 Pro, 48 GB memory
- Architecture: arm64
- Operating system: macOS 26.2
- Runtime: CTranslate2 INT8, Ruy INT8 GEMM, Accelerate FP32 operations
- Models: OPUS-MT English ↔ Chinese language packs
- Measurement: Mach task RSS and `phys_footprint` sampled at process baseline, tokenizer load, model load, warm inference and unload stages

Results are hardware- and build-specific. Raw development logs are intentionally not version-controlled.
