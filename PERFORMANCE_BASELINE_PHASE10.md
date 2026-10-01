# 第 10 阶段：目录导入收尾配对基准

Merchant 导入不会修改 ads_product_daily、sales_daily 或事实中的 product_id，因此无需重新聚合周指标。本轮移除这次全量扫描与重写，保留筛选目录更新、GMC 缺失对账和看板刷新。

## 方法与结果

macOS Release，命令启用 ENABLE_TESTABILITY=YES 以运行 @testable 测试，未改动项目配置。合成 500 个产品、10,000 条投放事实，20 天跨度；使用同一内存数据库，旧/新路径交替先后执行。首对预热后各 11 次，p50 取排序中位值，p95 取 ceil(n×0.95) 的次序统计量（11 样本时等于最大值）。

旧路径测量 hasFactTableData、全量 rebuildProductWeeklyMetrics 和 reconcileOrphanProducts；新路径调用实际 finishImport，进度、筛选目录和刷新回调为空。文件解析、商品写入、筛选目录构建、UI 刷新和磁盘成本均未计入。每次旧路径重写缓存仍使数据量一致，测试检查周表行数不变；另有回归测试逐字段比较目录更新前后的周记录。

| 收尾数据库工作 | p50 (ms) | p95 (ms) |
| --- | ---: | ---: |
| 旧路径：包含全量周重建 | 21.265 | 22.261 |
| 新路径：省去全量周重建 | 0.706 | 0.729 |

这是这段冗余计算被移除的证据，不代表整次导入或页面加载的加速比例；实际大账户、磁盘数据库和 UI 响应需要本地验证。投放/销售导入仍执行全量重建，本轮没有实现其增量重建。

## 验证来源

- Debug 定向回归：19 个通过，日志 `/private/tmp/pla-phase10-tests-20261001.log`。
- Release：4 个导入收尾回归及 1 个基准通过，日志 `/private/tmp/pla-phase10-release-20261001.log`。
- xcresult：`/private/tmp/pla-phase6-release-20261001/Logs/Test/Test-PLADashboard-2026.10.01_15-19-18-+0800.xcresult`。
- 导出的原始计时附件：`/private/tmp/pla-phase10-attachments/416D5D1B-94ED-4A55-9245-B82E5E2D3FBA.json`。
- 测试：`ImportFinishTests.swift`、`MerchantFinishPerformanceTests.swift`。
