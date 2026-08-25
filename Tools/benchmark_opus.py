#!/usr/bin/env python3
"""Development-only benchmark for converted OPUS-MT CTranslate2 models."""

import statistics
import time
from pathlib import Path

import ctranslate2
import sentencepiece as spm

ROOT = Path(__file__).resolve().parents[1]


def translate(model_dir: Path, source_spm: Path, target_spm: Path, text: str) -> tuple[str, float]:
    source = spm.SentencePieceProcessor(model_file=str(source_spm))
    target = spm.SentencePieceProcessor(model_file=str(target_spm))
    engine = ctranslate2.Translator(str(model_dir), device="cpu", inter_threads=1, intra_threads=2)
    started = time.perf_counter()
    result = engine.translate_batch([source.encode(text, out_type=str) + ["</s>"]], beam_size=4)
    elapsed_ms = (time.perf_counter() - started) * 1_000
    return target.decode(result[0].hypotheses[0]), elapsed_ms


def main() -> None:
    cases = [
        ("en-zh", "That sounds like a good idea."),
        ("zh-en", "这听起来是个好主意。"),
    ]
    for direction, text in cases:
        package = ROOT / "Models" / "LanguagePacks" / f"opus-mt-{direction}-int8" / "1.0.0"
        model = package / "ct2" / "model"
        source = package / "sentencepiece" / "source.spm"
        target = package / "sentencepiece" / "target.spm"
        times = []
        result = ""
        for _ in range(6):
            result, elapsed = translate(model, source, target, text)
            times.append(elapsed)
        print(f"{direction}: {result}")
        print(f"  warm P50: {statistics.median(times[1:]):.1f} ms")


if __name__ == "__main__":
    main()
