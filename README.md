# PLA Dashboard

Google 购物广告产品数据看板 — macOS 本地应用。

## 技术栈

- SwiftUI + Observation
- SQLite + GRDB.swift
- App Sandbox

## 构建

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' build
```

## 工程结构

- 方案文档：`../Vibe Coding/PLA_Dashboard_产品数据看板需求与技术栈方案_2026-06-22.md`
- PRD / 开发进度：`../Vibe Coding/PLA_Dashboard_PRD.md`、`../Vibe Coding/PLA_Dashboard_开发进度.md`
- 类目预览数据：`PLADashboard/Resources/ProductCategoryCatalog.json`（由样例 TSV `google 商品类别` 列生成）
