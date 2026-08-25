# Benchmarks

`native-memory-benchmark.csv` records the native runtime memory-attribution run used for the current baseline.

- Machine: MacBook Pro with Apple M4 Pro, 48 GB memory
- Architecture: arm64
- Operating system: macOS 26.2
- Runtime: CTranslate2 INT8, Ruy INT8 GEMM, Accelerate FP32 operations
- Models: OPUS-MT English ↔ Chinese language packs
- Measurement: Mach task RSS and `phys_footprint` sampled at process baseline, tokenizer load, model load, warm inference and unload stages

Results are hardware- and build-specific. Raw development logs are intentionally not version-controlled.

## Current baseline

- One-model warm `phys_footprint`: 168.67 MiB
- Two-model warm `phys_footprint`: 296.95 MiB
- After unloading both models: 58.28 MiB
- Memory growth across 100 warm requests: less than 1 MiB in each direction
- Separate native throughput run: approximately 1.95 seconds for 100 warm requests (19.5 ms per request on average)

The throughput figure measures the native backend only. It is not a claim about end-to-end selection, Accessibility, popup, or rendering latency.

Regenerate the README chart after changing the CSV:

```bash
python3 Tools/generate_benchmark_chart.py
```
