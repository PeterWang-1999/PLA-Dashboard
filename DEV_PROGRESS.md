# PLA Dashboard — 开发进度

> 本地开发追踪文档。每次代码修改后由 Agent 更新。

## 当前阶段

看板底栏显示报告周期（如 当前报告周期：2026-W22 至 2026-W27）— **已完成**（2026-07-10）

- 目标：在产品数据底栏左侧展示当前 6 个完整报告周的周次范围

## 变更记录

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
