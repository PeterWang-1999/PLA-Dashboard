# PLA Dashboard 性能基准

## 运行基准

在仓库根目录使用完整的 Xcode。Release 测试命令临时启用 `ENABLE_TESTABILITY`，使测试目标能通过 `@testable import` 加载应用模块。

```bash
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -testPlan PLADashboardPerformance \
  -configuration Release \
  -destination 'platform=macOS' \
  ENABLE_TESTABILITY=YES test
```

如果使用本地临时签名且测试宿主因 Team ID 校验拒绝加载测试包，可在本次测试命令中加入 `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO`。这些参数仅用于本地测试构建。

性能计划运行 `AdsImportPerformanceTests` 和 `DashboardQueryPerformanceTests`。如需重跑表格中的其他对照，将 `-testPlan PLADashboardPerformance` 替换为 `-testPlan PLADashboardDefault`，再加上目标测试类，例如 `-only-testing:PLADashboardTests/IncrementalWeeklyMetricsPerformanceTests`。

导入与查询基准默认使用 10,000 条 Ads 明细和 500 条 Merchant SKU。百万行导入可先生成测试文件，再在 Xcode 的 **Edit Scheme → Test → Arguments** 中给测试进程添加环境变量 `PLA_RUN_FULL_BENCHMARK=1`，运行 `AdsImportPerformanceTests/testAdsImportAndETLWithinReasonableTime`。缺少文件或环境变量时，该用例使用默认数据量。

```bash
python3 Scripts/generate_ads_benchmark.py --ads-rows 1000000 --merchant-rows 50000
```

文件生成到 `BenchmarkFixtures/`。应用的导入批大小为 1,000 行。需要测量真实账户时，可在 Release 构建中用 Time Profiler 和 Allocations 分别观察导入、周聚合、分页和图片解码。数据库测试与实际页面交互使用不同的计时范围。

## 历史 Release 对照

以下是合成数据和内存数据库的历史结果，耗时为毫秒，依次列出 p50 和 p95。每项预热后取 11 个样本，最近秩法下 p95 对应该组最大值。表格中的各场景有独立的工作量和测试条件。当前文档整理未重测整页加载、真实账户磁盘耗时或峰值内存。

| 场景 | 对照 p50 / p95 | 优化后 p50 / p95 | 条件与复跑用例 |
| --- | ---: | ---: | --- |
| 可见页面刷新 | 75.936 / 81.298 | 72.285 / 155.220 | 500 产品、10,000 投放行。比较产品表加图表与仅图表，p95 上升。 `VisiblePageQueryBaselineTests` |
| 移除预警后的查询工作量 | 82.092 / 86.571 | 78.958 / 80.941 | 同一版本、500 产品、10,000 投放行。比较产品表加图表与仅图表。 `VisiblePageQueryBaselineTests` |
| 图表 SQL 汇总 | 78.958 / 80.941 | 75.155 / 79.504 | 同规模，仅图表。前后独立运行。 `VisiblePageQueryBaselineTests` |
| Merchant 目录导入收尾 | 21.265 / 22.261 | 0.706 / 0.729 | 同库交替测量，500 产品、10,000 投放行。只计数据库收尾，回调为空。 `MerchantFinishPerformanceTests` |
| 重复查询产品表第一页 | 6.041 / 7.327 | 5.227 / 5.630 | 2,000 产品、40,000 投放行，每页 30 行，暖查询，前后独立运行。 `DashboardPageLoadPerformanceTests` |
| 查询产品表第 30 页 | 7.512 / 7.727 | 6.561 / 6.872 | 同上。 |
| 按自定义标签 EN 查询 | 9.484 / 9.693 | 6.721 / 7.041 | 同上。 |
| 按产品 ID 搜索 | 0.983 / 1.245 | 0.931 / 0.948 | 同上。 |
| 投放周指标全量与增量重算 | 72.816 / 80.195 | 2.900 / 3.064 | 同库交替测量，1,000 产品、20,000 投放行，新增文件 40 行，影响 10 产品。 `IncrementalWeeklyMetricsPerformanceTests` |
| 销售周指标全量与增量重算 | 56.427 / 62.537 | 2.130 / 4.079 | 同规模，新增文件 10 行，影响 10 产品。 `IncrementalWeeklyMetricsPerformanceTests` |

增量重算计时只覆盖周指标写入与计算。待重算记录准备单独计时，投放为 0.300 / 0.513 ms，销售为 0.268 / 0.448 ms。测试逐字段核对增量结果与全量重算一致。旧账户首次建立基线、手动重建和保留期清理仍使用全量路径。

图片优化使用合成 JPEG 验证后台缩略、缓存复用、共享下载和取消行为，测试类为 `ProductImageLoaderTests`。2× 显示器下，表格、Top 10 和详情请求的缩略图最长边分别为 80、144 和 560 像素。历史测试覆盖的是资源工作量和并发行为。

各轮原始报告、方法和验证记录可查阅 [整理前的 Git 快照](https://github.com/PeterWang-1999/PLA-Dashboard/tree/75f2961522476a3df3ece8f9af5064caa3e54238)。
