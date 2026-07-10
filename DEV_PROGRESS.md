# PLA Dashboard — 开发进度

> 本地开发追踪文档。每次代码修改后由 Agent 更新。

## 当前阶段

投放产品明细导入进度条（写入条数）— **已完成**（2026-07-10）

- 目标：XLSX/CSV 导入显示与其他数据源一致的「写入数据库」确定进度（已处理 / 总行数）

## 变更记录

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
