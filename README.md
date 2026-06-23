# PLA Dashboard

Google 购物广告产品数据看板 — macOS 本地应用。

## 开发要求

- 每次代码变更前请访问“https://developer.apple.com/documentation/swiftui” 和 “https://developer.apple.com/documentation/samplecode” 并查找其中的内容，确保当前修改方案与苹果官方指引完全一致，使用官方组件及API，不得自由发挥
- 每次修改完成后请对“/Users/litb/Library/Mobile\ Documents/com\~apple\~CloudDocs/1-个人/个人项目/Vibe\ Coding/PLA_Dashboard_PRD.md” 和 “/Users/litb/Library/Mobile\ Documents/com\~apple\~CloudDocs/1-个人/个人项目/Vibe\ Coding/PLA_Dashboard_开发进度.md” 内容进行更新

## 技术栈

- SwiftUI + Observation
- SQLite + GRDB.swift
- App Sandbox

## 构建

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' build
```

## 性能基准（阶段 5）

```bash
# 功能 + 性能回归（Debug，含 10k 行基准）
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test

# Release 性能 Test Plan（仅性能用例）
xcodebuild -scheme PLADashboard -testPlan PLADashboardPerformance \
  -destination 'platform=macOS' test

# 生成百万行 fixture（不入 Git）
python3 Scripts/generate_ads_benchmark.py --ads-rows 1000000 --merchant-rows 50000

# 完整百万行基准
PLA_RUN_FULL_BENCHMARK=1 xcodebuild -scheme PLADashboard -testPlan PLADashboardPerformance \
  -destination 'platform=macOS' test
```

详见仓库内 [BenchmarkReport.md](BenchmarkReport.md)。

## 工程结构

- 方案文档：`../Vibe Coding/PLA_Dashboard_产品数据看板需求与技术栈方案_2026-06-22.md`
- PRD / 开发进度：`../Vibe Coding/PLA_Dashboard_PRD.md`、`../Vibe Coding/PLA_Dashboard_开发进度.md`
- 类目预览数据：`PLADashboard/Resources/ProductCategoryCatalog.json`（由样例 TSV `google 商品类别` 列生成）
- 自定义标签预览数据：`PLADashboard/Resources/ProductCustomLabelCatalog.json`（由样例 TSV `自定义标签 0`…`4` 列生成）
