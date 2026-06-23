#!/usr/bin/env python3
"""生成 PLA Dashboard 阶段 5 基准 fixture（Ads CSV + Merchant TSV + manifest.json）。"""

from __future__ import annotations

import argparse
import csv
import json
import random
from datetime import date, timedelta
from pathlib import Path

ADS_HEADER_LINES = [
    "Ador - 产品数据",
    "2026-06-01 - 2026-06-22",
]
ADS_COLUMNS = [
    "天",
    "产品 ID",
    "广告系列",
    "货币代码",
    "费用",
    "展示次数",
    "点击次数",
    "转化次数",
    "转化价值",
]

MERCHANT_HEADER = [
    "标题",
    "序号",
    "canonical link",
    "图片链接",
    "自定义标签 0",
    "自定义标签 1",
    "自定义标签 2",
    "自定义标签 3",
    "自定义标签 4",
    "google 商品类别",
]


def product_id_for_index(i: int) -> str:
    return f"bench_{i:08d}_00001_US_en"


def generate_merchant_row(i: int) -> list[str]:
    pid = product_id_for_index(i)
    return [
        f"Bench Product {i}",
        pid,
        f"https://example.com/p/{i}",
        f"https://example.com/img/{i}.jpg",
        "EN",
        "",
        "",
        "",
        "",
        "Apparel & Accessories > Clothing > Shirts & Tops",
    ]


def generate_ads_row(
    row_index: int,
    day: date,
    product_index: int,
    rng: random.Random,
) -> tuple[list[str], dict]:
    pid = product_id_for_index(product_index)
    cost = round(rng.uniform(1.0, 50.0), 2)
    impressions = rng.randint(100, 5000)
    clicks = rng.randint(1, max(2, impressions // 20))
    conversions = round(rng.uniform(0.0, clicks / 10.0), 1)
    conv_value = round(conversions * rng.uniform(20.0, 80.0), 2)
    row = [
        day.isoformat(),
        pid,
        "Campaign Bench",
        "USD",
        f"{cost:.2f}",
        str(impressions),
        str(clicks),
        f"{conversions:.1f}",
        f"${conv_value:.2f}",
    ]
    manifest_entry = {
        "row_number": row_index + 4,  # 1-based file line after 2 headers + column header
        "date": day.isoformat(),
        "product_id": pid.split("_")[1] if pid.startswith("bench_") else pid,
        "item_id": pid,
        "cost_micros": int(round(cost * 1_000_000)),
        "conversion_value_cents": int(round(conv_value * 100)),
    }
    return row, manifest_entry


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate PLA Dashboard benchmark fixtures")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "BenchmarkFixtures",
    )
    parser.add_argument("--ads-rows", type=int, default=1_000_000)
    parser.add_argument("--merchant-rows", type=int, default=50_000)
    parser.add_argument("--days", type=int, default=20)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)

    start_day = date(2026, 6, 1)
    days = [start_day + timedelta(days=d) for d in range(args.days)]

    ads_path = args.output_dir / ("Ads_1M.csv" if args.ads_rows >= 1_000_000 else f"Ads_{args.ads_rows}.csv")
    merchant_path = args.output_dir / (
        "Merchant_50K.tsv" if args.merchant_rows >= 50_000 else f"Merchant_{args.merchant_rows}.tsv"
    )
    manifest_path = args.output_dir / "Ads_manifest.json"

    product_count = max(args.merchant_rows, (args.ads_rows // max(1, args.days)) + 1)

    print(f"Writing Merchant {args.merchant_rows} rows -> {merchant_path}")
    with merchant_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(MERCHANT_HEADER)
        for i in range(args.merchant_rows):
            writer.writerow(generate_merchant_row(i))

    manifest_samples: list[dict] = []
    sample_stride = max(1, args.ads_rows // 100)

    print(f"Writing Ads {args.ads_rows} rows -> {ads_path}")
    with ads_path.open("w", encoding="utf-8", newline="") as f:
        f.write(ADS_HEADER_LINES[0] + "\n")
        f.write(ADS_HEADER_LINES[1] + "\n")
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(ADS_COLUMNS)
        for row_index in range(args.ads_rows):
            product_index = row_index % product_count
            day = days[row_index % len(days)]
            row, entry = generate_ads_row(row_index, day, product_index, rng)
            writer.writerow(row)
            if row_index % sample_stride == 0:
                manifest_samples.append(entry)

    manifest_path.write_text(
        json.dumps({"samples": manifest_samples, "ads_rows": args.ads_rows, "seed": args.seed}, indent=2),
        encoding="utf-8",
    )
    print(f"Wrote manifest ({len(manifest_samples)} samples) -> {manifest_path}")
    print("Done.")


if __name__ == "__main__":
    main()
