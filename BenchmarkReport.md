# PLA Dashboard 性能基准报告

更新日期：2026-06-23

## 参考环境

- 配置：Apple Silicon Mac（本地 Debug 功能测试 / Release 性能 Test Plan）
- macOS：14.4+
- 导入批大小：`BenchmarkConfiguration.importBatchSize` = **1000**
- 默认性能测试规模：**10,000** Ads 行 + **500** Merchant SKU
- 完整基准：`PLA_RUN_FULL_BENCHMARK=1` + `BenchmarkFixtures/Ads_1M.csv`

## 优化摘要（阶段 5）

| 领域 | 变更 |
|------|------|
| 索引 | Migration v4：`import_jobs(checksum,status)`、`ads_product_daily(import_id)`、`product_weekly_metrics(week_start)` |
| 导入 | Ads 多行 `INSERT OR REPLACE`；Merchant 单事务 flush；产品 upsert 批量 fetch |
| ETL | `rebuildProductWeeklyMetrics` 下沉 SQL `INSERT…SELECT` + 周日起算 |
| FTS | Merchant 导入后全量 `rebuildAllProductSearchIndex` |
| 看板 | SQL `LIMIT/OFFSET` 分页；overall/cohort 缓存；`OSSignpost` 标记 |

## 验收指标（方案 §13）

| 指标 | 目标 | 验证方式 |
|------|------|----------|
| 看板首屏 | 300–800 ms（Release 参考机） | `DashboardQueryPerformanceTests.testDashboardQueryWithinSLA` |
| DB 分页 | 每页 ≤30 行 | `testDashboardPageReturnsOnlyPageSizeRows` |
| 索引 / 非全表扫描 | FTS + weekly 索引 | `QueryPlanTests` |
| 金额准确性 | 与源文件一致 | `ImportAccuracyTests`、`WeeklyMetricsAccuracyTests` |
| Ads 10k 导入 + ETL | < 120 s（Debug 内存库） | `AdsImportPerformanceTests` |

## 生成百万行 Fixture

```bash
python3 Scripts/generate_ads_benchmark.py --ads-rows 1000000 --merchant-rows 50000
```

输出目录：`BenchmarkFixtures/`（已 `.gitignore`）

## 运行性能 Test Plan（Release）

```bash
xcodebuild -scheme PLADashboard -testPlan PLADashboardPerformance \
  -destination 'platform=macOS' test
```

完整百万行：

```bash
PLA_RUN_FULL_BENCHMARK=1 xcodebuild -scheme PLADashboard -testPlan PLADashboardPerformance \
  -destination 'platform=macOS' test
```

## Instruments（手动）

导入 1M 时建议 Profile：

- **Time Profiler**：确认主线程无长时间解析栈帧
- **Allocations**：观察 Ads 导入峰值内存
- 搜索 `import.flush` / `etl.rebuild` / `dashboard.fetchPage` signpost
