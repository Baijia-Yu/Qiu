#!/usr/bin/env python3
"""Generate the README memory chart from the checked-in benchmark CSV."""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Benchmarks" / "native-memory-benchmark.csv"
OUTPUT = ROOT / "Benchmarks" / "memory-profile.svg"


def load_rows() -> list[dict[str, str]]:
    with SOURCE.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def first(rows: list[dict[str, str]], stage: str, direction: str, request: int = 0) -> float:
    for row in rows:
        if (
            row["stage"] == stage
            and row["direction"] == direction
            and int(row["request"]) == request
        ):
            return float(row["phys_footprint_mib"])
    raise ValueError(f"Missing benchmark row: {stage}/{direction}/{request}")


def esc(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def main() -> None:
    rows = load_rows()
    stages = [
        ("Baseline", first(rows, "baseline", "none")),
        ("Tokenizer", first(rows, "sentencepiece_ready", "en_zh")),
        ("Model ready", first(rows, "model_loaded", "en_zh")),
        ("1 model warm", first(rows, "inference", "en_zh", 100)),
        ("2 models warm", first(rows, "inference", "both", 2)),
        ("All unloaded", first(rows, "both_unloaded", "none")),
    ]
    warm = {
        direction: [
            (int(row["request"]), float(row["phys_footprint_mib"]))
            for row in rows
            if row["stage"] == "inference" and row["direction"] == direction
        ]
        for direction in ("en_zh", "zh_en")
    }

    width, height = 1200, 650
    ink, muted, grid = "#172033", "#667085", "#E4E7EC"
    pink, purple, coral = "#D92D72", "#7F56D9", "#FF5A5F"
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}",
        ".title{font-size:30px;font-weight:700;fill:#172033}.subtitle{font-size:15px;fill:#667085}",
        ".panel{font-size:18px;font-weight:650;fill:#172033}.axis{font-size:12px;fill:#667085}",
        ".label{font-size:13px;fill:#344054}.value{font:600 13px ui-monospace,SFMono-Regular,Menlo,monospace;fill:#172033}",
        "</style>",
        '<rect width="1200" height="650" rx="24" fill="#FFFFFF"/>',
        '<rect x="1" y="1" width="1198" height="648" rx="23" fill="none" stroke="#EAECF0"/>',
        f'<text x="48" y="55" class="title">Qiu native memory profile</text>',
        f'<text x="48" y="82" class="subtitle">Physical footprint (MiB) · Apple M4 Pro · macOS 26.2 · CTranslate2 INT8 + Ruy</text>',
        '<text x="48" y="126" class="panel">Memory by lifecycle stage</text>',
        '<text x="640" y="126" class="panel">100-request warm stability</text>',
        '<text x="640" y="149" class="subtitle">Focused scale: 160–200 MiB · sequential direction runs</text>',
    ]

    # Left: horizontal stage comparison, zero-based scale.
    left_x, left_y, chart_w, row_h = 170, 166, 390, 58
    max_value = 320.0
    for tick in (0, 100, 200, 300):
        x = left_x + chart_w * tick / max_value
        parts.append(f'<line x1="{x:.1f}" y1="{left_y}" x2="{x:.1f}" y2="{left_y + 340}" stroke="{grid}"/>')
        parts.append(f'<text x="{x:.1f}" y="{left_y + 360}" text-anchor="middle" class="axis">{tick}</text>')
    for index, (label, value) in enumerate(stages):
        y = left_y + index * row_h + 13
        bar_width = chart_w * value / max_value
        fill = pink if label in {"1 model warm", "2 models warm"} else "#E9D7FE"
        if label == "All unloaded":
            fill = coral
        parts.append(f'<text x="48" y="{y + 16}" class="label">{esc(label)}</text>')
        parts.append(f'<rect x="{left_x}" y="{y}" width="{bar_width:.1f}" height="25" rx="7" fill="{fill}"/>')
        parts.append(f'<text x="{left_x + bar_width + 8:.1f}" y="{y + 17}" class="value">{value:.0f}</text>')

    # Right: warm stability lines with a deliberately focused y-axis.
    plot_x, plot_y, plot_w, plot_h = 680, 180, 450, 305
    y_min, y_max = 160.0, 200.0
    for tick in (160, 170, 180, 190, 200):
        y = plot_y + plot_h * (y_max - tick) / (y_max - y_min)
        parts.append(f'<line x1="{plot_x}" y1="{y:.1f}" x2="{plot_x + plot_w}" y2="{y:.1f}" stroke="{grid}"/>')
        parts.append(f'<text x="{plot_x - 12}" y="{y + 4:.1f}" text-anchor="end" class="axis">{tick}</text>')
    for tick in (1, 25, 50, 75, 100):
        x = plot_x + plot_w * (tick - 1) / 99
        parts.append(f'<text x="{x:.1f}" y="{plot_y + plot_h + 24}" text-anchor="middle" class="axis">{tick}</text>')
    parts.append(f'<text x="{plot_x + plot_w / 2:.1f}" y="{plot_y + plot_h + 48}" text-anchor="middle" class="axis">Warm request</text>')

    for direction, color, label in (
        ("en_zh", pink, "EN → ZH"),
        ("zh_en", purple, "ZH → EN"),
    ):
        points = []
        for request, value in warm[direction]:
            x = plot_x + plot_w * (request - 1) / 99
            y = plot_y + plot_h * (y_max - value) / (y_max - y_min)
            points.append(f"{x:.1f},{y:.1f}")
        parts.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{color}" stroke-width="3"/>')
        end_value = warm[direction][-1][1]
        end_y = plot_y + plot_h * (y_max - end_value) / (y_max - y_min)
        parts.append(f'<circle cx="{plot_x + plot_w}" cy="{end_y:.1f}" r="4" fill="{color}"/>')
        parts.append(f'<text x="{plot_x + plot_w - 8}" y="{end_y - 10:.1f}" text-anchor="end" class="value" fill="{color}">{label} {end_value:.1f}</text>')

    parts.extend(
        [
            '<rect x="48" y="570" width="1104" height="1" fill="#EAECF0"/>',
            '<text x="48" y="600" class="subtitle">Takeaway: memory reaches a plateau after the first inference; no meaningful creep across 100 warm requests.</text>',
            '<text x="48" y="625" class="axis">Source: Benchmarks/native-memory-benchmark.csv · Results are hardware- and build-specific.</text>',
            "</svg>",
        ]
    )
    OUTPUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(OUTPUT)


if __name__ == "__main__":
    main()
