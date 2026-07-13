# PLA Dashboard — 开发进度

> 本地开发追踪文档。每次代码修改后由 Agent 更新。

## 当前阶段

优化看板翻页性能 — **已完成**（2026-07-13）

- 目标：自建站预警筛选 SQL 真分页；翻页轻量 loading；标签快照缓存

## 变更记录

### 2026-07-13 — 优化看板翻页性能

**内容**

- 自建站按预警标签筛选：`JOIN label_snapshot_products` + `LIMIT/OFFSET`，翻页不再全量扫描
- 标签决策按最新 `week_id` 缓存，随 `invalidateDashboardCache` 失效
- 翻页使用 `isPaging`：不整表 disabled、不盖右上角转圈；底栏保留轻量指示
- 产品图加载占位改为静态图 + 小菊花，减少翻页时满屏 Progress
- 导出路径对自建站预警筛选同步走 SQL 过滤

**涉及文件**

- `PLADashboard/Data/Database/DatabaseClient.swift`
- `PLADashboard/Data/Database/DatabaseClient+Dashboard.swift`
- `PLADashboard/Features/Dashboard/DashboardViewModel.swift`
- `PLADashboard/Features/Dashboard/DashboardView.swift`
- `PLADashboard/Features/Dashboard/ProductImageView.swift`
- `PLADashboardTests/SelfBuiltWarningLabelDashboardTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild … test \
  -only-testing:PLADashboardTests/SelfBuiltWarningLabelDashboardTests \
  -only-testing:PLADashboardTests/DashboardFilterTests \
  -only-testing:PLADashboardTests/DashboardViewModelAccountSwitchTests
# TEST SUCCEEDED
```

### 2026-07-11 — 修复超长小数毛利入库为 0

**内容**

- 根因：Product Sales 的 `毛利额($)` 常含 30+ 位小数；`NSDecimalMultiplyByPowerOf10` 后直接取 `NSDecimalNumber.intValue` 会误返回 0，约 1/3 正毛利行丢失
- `parseCurrencyToCents` / `parseCostToMicros`：先按目标小数位舍入再缩放取整
- 单测覆盖超长小数解析与导入后 `gross_profit_cents` 非零

**涉及文件**

- `PLADashboard/Data/Import/ImportValueParsers.swift`
- `PLADashboardTests/ImportValueParsersTests.swift`
- `PLADashboardTests/SalesReportImporterTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild … test -only-testing:PLADashboardTests/ImportValueParsersTests \
  -only-testing:PLADashboardTests/SalesReportImporterTests \
  -only-testing:PLADashboardTests/WeeklyMetricsAggregatorTests
# TEST SUCCEEDED

touch /tmp/pla_e2e_label_files && xcodebuild … test \
  -only-testing:PLADashboardTests/SelfBuiltLabelEngineE2ETests
# TEST SUCCEEDED（约 87s）
# 普通/观察=10974 低样本老品=530 潜力新品=174 高效=65 低效=50
```

**下一步**

- 现有账户：设置 →「重新计算预警标签」，或重导 Product Sales 后再算

### 2026-07-11 — 修复周表只保留投放周导致毛利/活跃周丢失

**内容**

- `rebuildProductWeeklyMetrics` 改为：有投放的产品 ×（投放周 ∪ 销售周）为键，再 LEFT JOIN 广告与销售指标
- 标签宇宙仅纳入报告窗内有过投放事实的产品
- 新增单测：销售落在无投放周时仍写入 GS/毛利
- E2E 断言改为与 Python 冷启动精确对齐（高效 65 / 潜力 174 / 老品 530 等）

**涉及文件**

- `PLADashboard/Data/Database/DatabaseClient+Analytics.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelMetricsBuilder.swift`
- `PLADashboard/Data/Database/DatabaseBulkInsert.swift`
- `PLADashboardTests/WeeklyMetricsAggregatorTests.swift`
- `PLADashboardTests/SelfBuiltLabelEngineE2ETests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
# 与「超长小数毛利」修复一并经真实文件 E2E 通过，见上条
```

### 2026-07-10 — 修复同周导入不重算 + PLA CMS3 + 真实文件 E2E

**内容**

- 根因：先导投放无毛利时算出「几乎全普通」快照后，再导 Product Sales 因同周已有快照被 `skippedAlreadyComputed` 跳过，标签不更新
- `recomputeWarningLabelsIfNeeded` 增加 `refreshSameWeek`；导入流水线对投放/毛利导入传 `true`，允许覆盖本周快照
- 设置页增加「重新计算预警标签」（同周刷新，不清空历史）
- 投放明细可选列 `CMS3` 按花费选主类目写入 `products.pla_cms3`；标签指标优先用 PLA CMS3
- 新增真实大文件 E2E 测试（`touch /tmp/pla_e2e_label_files` 触发）

**涉及文件**

- `PLADashboard/Data/Analytics/LabelEngine/DatabaseClient+LabelCompute.swift`
- `PLADashboard/Data/Analytics/LabelEngine/DatabaseClient+LabelMetrics.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelProductMetrics.swift`
- `PLADashboard/Data/Import/ImportPipelineRunner.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailColumnMap.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailImporter.swift`
- `PLADashboard/Data/Database/Migrations/Migration_v8_ProductPlaCMS3.swift`
- `PLADashboard/Data/Database/Migrations/DatabaseMigrator.swift`
- `PLADashboard/Data/Database/Records/ProductRecord.swift`
- `PLADashboard/Data/Database/DatabaseClient+Import.swift`
- `PLADashboard/Data/Database/ProductCatalogMerge.swift`
- `PLADashboard/Features/Settings/SettingsView.swift`
- `PLADashboardTests/LabelStateMachineTests.swift`
- `PLADashboardTests/PlaDeliveryDetailImporterTests.swift`
- `PLADashboardTests/SelfBuiltLabelEngineE2ETests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
# 单元：同周 skip / refreshSameWeek、CMS3 按花费入库 — TEST SUCCEEDED

# 真实文件 E2E（约 98s）— TEST SUCCEEDED
# 先导 PLA 仅毛利缺失：普通/观察=11738，低效=55（几乎全普通）
# 再导 Sales 同周刷新后：
#   total=11793
#   普通/观察=11248  低样本老品=350  潜力新品=110  高效=33  低效=52
```

**下一步**

- 用户在已有账户上：设置 →「重新计算预警标签」，或重新导入毛利文件即可刷新

### 2026-07-10 — Phase 4：Python 对照用例与回归

**内容**

- 状态机补充对照：分位缺失时潜力仅走 ROI、旧 flag 不误作出池、高效首次未达标暂留、潜力晋升高效、低样本老品入池、上周快照可读
- 回归：`WeeklyMetricsRulesTests`（三方站旧标签）、周聚合、看板筛选、销售导入、类目 CMS3、自建站看板标签

**涉及文件**

- `PLADashboardTests/LabelStateMachineTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/LabelStateMachineTests \
  -only-testing:PLADashboardTests/LabelMetricsBuilderTests \
  -only-testing:PLADashboardTests/SelfBuiltWarningLabelDashboardTests \
  -only-testing:PLADashboardTests/WeeklyMetricsRulesTests \
  -only-testing:PLADashboardTests/WeeklyMetricsAggregatorTests \
  -only-testing:PLADashboardTests/DashboardFilterTests \
  -only-testing:PLADashboardTests/SalesReportImporterTests \
  -only-testing:PLADashboardTests/ProductCategoryPathTests
# TEST SUCCEEDED
```

**下一步**

- 等待确认后可将本轮标为全部完成；可选：用真实 PLA+毛利大文件做一次端到端人工验收

### 2026-07-10 — Phase 3：看板接线与一键 reset

**内容**

- 自建站看板通过 `WarningLabelEngine.selfBuiltSnapshot` 读取最新周快照标签；无快照显示「—」；「普通/观察」显式展示
- 预警筛选选项按账户类型切换（高效/潜力新品/低样本老品/低效/普通/观察）
- 标签胶囊样式补充高效、潜力新品、低样本老品、普通/观察
- 设置页：自建站隐藏旧 ROI 门槛，提供「重置预警标签历史」→ `force` 重算
- 快照标签按页批量加载一次，避免筛选分页重复读库

**涉及文件**

- `PLADashboard/Data/Analytics/WeeklyMetricsRules.swift`
- `PLADashboard/Data/Analytics/ProductPerformanceRowMapper.swift`
- `PLADashboard/Data/Database/DatabaseClient+Dashboard.swift`
- `PLADashboard/Domain/ProductPerformanceRowModel.swift`
- `PLADashboard/Features/Dashboard/ProductPerformanceRow.swift`
- `PLADashboard/Features/Dashboard/DashboardViewModel.swift`
- `PLADashboard/Features/Dashboard/DashboardToolbarComponents.swift`
- `PLADashboard/Features/Settings/SettingsView.swift`
- `PLADashboard/App/RootView.swift`
- `PLADashboardTests/SelfBuiltWarningLabelDashboardTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/SelfBuiltWarningLabelDashboardTests \
  -only-testing:PLADashboardTests/LabelStateMachineTests \
  -only-testing:PLADashboardTests/DashboardViewModelAccountSwitchTests
# TEST SUCCEEDED
```

**下一步**

- 等待确认后进入 Phase 4：与 Python 黄金对照补充、回归三方站旧标签

### 2026-07-10 — Phase 2：状态机、快照与触发重算

**内容**

- 新增 `LabelStateMachine`：高效/潜力新品/低样本老品/低效的入池、留池、出池、暂留（对标 Python）
- 迁移 `v7_label_snapshots`：`label_snapshots` + `label_snapshot_products`（保留最近 26 周）
- `recomputeWarningLabelsIfNeeded`：仅当出现比已有快照更新的完整报告周时重算；`force` 清空历史后仅入池
- 自建站导入投放明细或 Product Sales 并重建周聚合后自动尝试重算
- 提供 `resetLabelHistory` / `loadLatestLabelDecisionsByProductId` 供 Phase 3 与设置页使用

**涉及文件**

- `PLADashboard/Data/Database/Migrations/Migration_v7_LabelSnapshots.swift`
- `PLADashboard/Data/Database/Migrations/DatabaseMigrator.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelSnapshotModels.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelStateMachine.swift`
- `PLADashboard/Data/Analytics/LabelEngine/DatabaseClient+LabelCompute.swift`
- `PLADashboard/Data/Import/ImportPipelineRunner.swift`
- `PLADashboard/Features/Imports/ImportViewModel.swift`
- `PLADashboardTests/LabelStateMachineTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/LabelStateMachineTests \
  -only-testing:PLADashboardTests/LabelMetricsBuilderTests
# TEST SUCCEEDED
```

**下一步**

- 等待确认后进入 Phase 3：看板展示新标签、筛选样式、设置页一键 reset

### 2026-07-10 — Phase 1：标签指标与基准引擎

**内容**

- 新增 `LabelEngine` 纯计算层：`LabelEngineConstants` / `LabelProductMetrics` / `LabelMetricsBuilder`
- 加权广告 ROI = Σ(CV×w)/Σ(Cost×w)；毛利回报、活跃周、新品 cutoff、Data_Normal 与 Python 对齐
- 类目样本不足回退全站基准；成熟毛利 P50、新品 GS P50/P75、老品 GS P50
- `DatabaseClient.buildLabelMetrics`：两次 SQL 批量读周表+产品维，内存聚合（避免逐产品查询）
- CMS3 使用 `ProductCategoryPath.cms3Leaf`（Merchant 末级）

**涉及文件**

- `PLADashboard/Data/Analytics/LabelEngine/LabelEngineConstants.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelProductMetrics.swift`
- `PLADashboard/Data/Analytics/LabelEngine/LabelMetricsBuilder.swift`
- `PLADashboard/Data/Analytics/LabelEngine/DatabaseClient+LabelMetrics.swift`
- `PLADashboardTests/LabelMetricsBuilderTests.swift`
- `DEV_PROGRESS.md`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/LabelMetricsBuilderTests
# TEST SUCCEEDED
```

**下一步**

- 等待确认后进入 Phase 2：入池/留池/出池状态机 + 周快照持久化 + 新完整周触发重算

### 2026-07-10 — Phase 0：标签引擎数据地基

**内容**

- 新增迁移 `v6_label_engine_data_foundation`：`sales_daily.gross_profit_cents`、`product_weekly_metrics.gross_profit_cents`、`products.first_listed_at`
- Product Sales 导入强制要求 `毛利额($)`，写入毛利分
- `rebuildProductWeeklyMetrics` 在单条 SQL 内 LEFT JOIN 去重后的销售周汇总（GS + 毛利），避免二次扫描
- 投放明细可选列 `首次上架时间`：导入结束批量 upsert，保留更早日期
- `ProductCategoryPath.cms3Leaf`：从 Merchant 类目路径取末级作为 CMS3
- 样例 CSV / 导入文案同步更新

**涉及文件**

- `PLADashboard/Data/Database/Migrations/Migration_v6_LabelEngineDataFoundation.swift`
- `PLADashboard/Data/Database/Migrations/DatabaseMigrator.swift`
- `PLADashboard/Data/Database/Records/SalesDailyRecord.swift`
- `PLADashboard/Data/Database/Records/ProductWeeklyMetricsRecord.swift`
- `PLADashboard/Data/Database/Records/ProductRecord.swift`
- `PLADashboard/Data/Database/DatabaseClient+Analytics.swift`
- `PLADashboard/Data/Database/DatabaseClient+Import.swift`
- `PLADashboard/Data/Database/ProductCatalogMerge.swift`
- `PLADashboard/Data/Import/SalesColumnMap.swift`
- `PLADashboard/Data/Import/SalesReportImporter.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailColumnMap.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailImporter.swift`
- `PLADashboard/Data/Import/MerchantCenterImporter.swift`
- `PLADashboard/Data/Analytics/WeeklyMetricsRules.swift`
- `PLADashboard/Domain/ProductCategoryPath.swift`
- `PLADashboard/Features/Imports/ImportsView.swift`
- `PLADashboard/Resources/SampleSales.csv`
- `PLADashboard/Resources/SamplePlaDeliveryDetail.csv`
- `PLADashboardTests/SalesReportImporterTests.swift`
- `PLADashboardTests/WeeklyMetricsAggregatorTests.swift`
- `PLADashboardTests/PlaDeliveryDetailImporterTests.swift`
- `PLADashboardTests/ProductCategoryPathTests.swift`
- `PLADashboardTests/LsinProductIDReconciliationTests.swift`
- `PLADashboardTests/LegacyDatabaseMigrationTests.swift`
- `PLADashboardTests/ImportTextEncodingTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/SalesReportImporterTests \
  -only-testing:PLADashboardTests/WeeklyMetricsAggregatorTests \
  -only-testing:PLADashboardTests/PlaDeliveryDetailImporterTests \
  -only-testing:PLADashboardTests/ProductCategoryPathTests \
  -only-testing:PLADashboardTests/LsinProductIDReconciliationTests \
  -only-testing:PLADashboardTests/LegacyDatabaseMigrationTests \
  -only-testing:PLADashboardTests/AccountStoreTests/testSelfBuiltAccountCanImportSampleSales
# TEST SUCCEEDED
```

**下一步**

- 等待确认后进入 Phase 1：Swift 指标/基准层（加权 ROI、类目基准、分位阈值）

### 2026-07-10 — 底栏左侧展示报告周期周次

**内容**

- `WeekCalendar` 按周结束周六的 ISO 周次生成 `yyyy-Www`（与业务 `week_mapping` 一致）
- `DashboardPageResult` 带回 `weekStarts`；ViewModel 生成 `reportingPeriodLabel`
- 底栏左侧以次要脚注样式显示，例如 `当前报告周期：2026-W22 至 2026-W27`；账户切换时清空

**涉及文件**

- `PLADashboard/Data/Analytics/WeekCalendar.swift`
- `PLADashboard/Data/Analytics/ProductPerformanceRowMapper.swift`
- `PLADashboard/Data/Database/DatabaseClient+Dashboard.swift`
- `PLADashboard/Features/Dashboard/DashboardViewModel.swift`
- `PLADashboard/Features/Dashboard/DashboardView.swift`
- `PLADashboardTests/WeekCalendarReportingWindowTests.swift`
- `PLADashboardTests/DashboardViewModelAccountSwitchTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/WeekCalendarReportingWindowTests \
  -only-testing:PLADashboardTests/DashboardViewModelAccountSwitchTests
# TEST SUCCEEDED
```

**补充**

- 文案改为带前缀：`当前报告周期：2026-W22 至 2026-W27`
### 2026-07-10 — 修复报告周锚定：排除不完整最新周

**内容**

- 根因：明细最新日为 2026-07-08（周三）时，旧逻辑以该日所在周为锚，6 周变成 05-31…07-05，丢掉完整的 05-24 周并纳入仅 4 天的残缺周 → S9730219 消费显示 5229.74
- Excel 全量合计 6984.70（含残缺周）；业务参考汇总 Cost_6w（W22–W27）为 6560.21
- `reportingWeekStarts` 改为先回退到不晚于最新日的最近周六，再取 6 个完整自然周
- 补充单测复现 5229.74 / 6560.20 / 6984.70 三组数字

**涉及文件**

- `PLADashboard/Data/Analytics/WeekCalendar.swift`
- `PLADashboardTests/WeekCalendarReportingWindowTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/WeekCalendarReportingWindowTests
# TEST SUCCEEDED
```

**下一步**

- 重新打开看板或点「刷新」验证 S9730219 消费约为 6560.21（非 Excel 全量 6984.7）

### 2026-07-10 — 投放产品明细导入补齐确定进度条

**内容**

- XLSX 解压后根据 `dimension`（或 `<row` 扫描）预估数据行数，写入 `totalRowsEstimate`
- 进度阶段与 Merchant/Ads 对齐：统计行数 → 解析 →「写入数据库」并显示 `processed / total`
- CSV 路径同样在统计后立即带上总行数

**涉及文件**

- `PLADashboard/Data/Import/XLSXSheetRowCounter.swift`
- `PLADashboard/Data/Import/StreamingXLSXRowParser.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailImporter.swift`
- `PLADashboardTests/XLSXSheetRowCounterTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/XLSXSheetRowCounterTests \
  -only-testing:PLADashboardTests/PlaDeliveryDetailImporterTests
# TEST SUCCEEDED
```

### 2026-07-10 — 支持 Merchant Center TSV 中英文列名

**内容**

- `MerchantCenterColumnMap` 按别名匹配表头：`序号/id`、`标题/title`、`图片链接/image link`、自建站 `链接/link`、三方站另接受 `link`、`自定义标签 n/custom label n`
- `CustomLabelCatalog` 解析英文自定义标签列时仍归一为中文列名供 UI 筛选
- 补充英文表头导入与列映射单测

**涉及文件**

- `PLADashboard/Data/Import/MerchantCenterColumnMap.swift`
- `PLADashboard/Data/Import/CustomLabelCatalog.swift`
- `PLADashboardTests/MerchantCenterImporterTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/MerchantCenterImporterTests
# TEST SUCCEEDED
```

### 2026-07-10 — 修复 XLSX shared strings 导致缺少「日期」列

**内容**

- 真实投放明细 xlsx 表头使用 `t="s"` 共享字符串索引，原先只解析 `inlineStr`/裸数值，表头变成 `0/1/2…`，误报缺少「日期」
- `StreamingXLSXRowParser` 增加 `xl/sharedStrings.xml` 加载与索引解析；补充 shared-strings 样例测试

**涉及文件**

- `PLADashboard/Data/Import/StreamingXLSXRowParser.swift`
- `PLADashboardTests/PlaDeliveryDetailImporterTests.swift`
- `PLADashboardTests/Fixtures/SamplePlaDeliveryDetailSharedStrings.xlsx`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/PlaDeliveryDetailImporterTests
# TEST SUCCEEDED
```


**内容**

- 新增 `ImportSourceKind.plaDeliveryDetail`；自建站能力改为 Merchant + 投放产品明细 + Product Sales
- `PlaDeliveryDetailImporter` 写入 `ads_product_daily`；`campaign=""`、`currency_code="USD"` 占位，不删列
- CSV：`linesToSkip = 0`；三方站 `AdsProductImporter.linesToSkip = 2` 不变
- 支持 XLSX：ZIP 解压（zlib raw DEFLATE）+ 流式 XML 行解析；staging 跳过二进制转码
- 自建站打开账户时 `purgeLegacyGoogleAdsImports()` 清除旧 `ads_product` 导入并重建周聚合

**涉及文件**

- `PLADashboard/Data/Import/PlaDeliveryDetailImporter.swift`
- `PLADashboard/Data/Import/PlaDeliveryDetailColumnMap.swift`
- `PLADashboard/Data/Import/StreamingXLSXRowParser.swift`
- `PLADashboard/Data/Import/ZipEntryExtractor.swift`
- `PLADashboard/Data/Import/ImportPipelineRunner.swift`
- `PLADashboard/Data/Import/ImportStagingStore.swift`
- `PLADashboard/Data/Import/ImportValueParsers.swift`
- `PLADashboard/Data/Database/Records/ImportJobRecord.swift`
- `PLADashboard/Data/Database/DatabaseClient.swift`
- `PLADashboard/Data/Database/DatabaseClient+Import.swift`
- `PLADashboard/Domain/WorkspaceCapabilities.swift`
- `PLADashboard/App/AccountStore.swift`
- `PLADashboard/App/RootView.swift`
- `PLADashboard/App/CreateAccountSheet.swift`
- `PLADashboard/Features/Imports/ImportsView.swift`
- `PLADashboard/Features/Dashboard/DashboardEmptyStateView.swift`
- `PLADashboard/Resources/SamplePlaDeliveryDetail.csv`
- `PLADashboardTests/PlaDeliveryDetailImporterTests.swift`
- `PLADashboardTests/Fixtures/SamplePlaDeliveryDetail.xlsx`
- `PLADashboardTests/WorkspaceCapabilitiesTests.swift`
- `PLADashboardTests/ImportValueParsersTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/PlaDeliveryDetailImporterTests \
  -only-testing:PLADashboardTests/PurgeLegacyGoogleAdsImportsTests \
  -only-testing:PLADashboardTests/WorkspaceCapabilitiesTests \
  -only-testing:PLADashboardTests/ImportValueParsersTests \
  -only-testing:PLADashboardTests/AdsProductImporterTests
# TEST SUCCEEDED
```

**下一步**

- 用真实大文件（约 17 万行 xlsx）在自建站账户做一次端到端导入验证性能与内存

## 历史记录（摘要）

此前阶段见 Git 历史；SHO 产品图加载率优化已于 2026-06-26 完成。
