# PLA Dashboard — 开发进度

> 本地开发追踪文档。每次代码修改后由 Agent 更新。

## 当前阶段

SHO 产品图加载率优化（重试修复 + 并发限流）— **已完成**（2026-06-26）

- 根因：重试时追加 `?reload=` 触发 CDN 403；每页 30 张图并发请求触发限流；Accept 协商可能返回 NSImage 无法解码的格式
- 实现：重试不改 URL、litbimg 去掉全部 query、3 路并发限流 + 403/502 退避重试、合并时优先无 query 图片链接

## 变更记录

### 2026-06-26 — 修复产品图重试无效与大部分加载失败

**内容**

- **重试 bug**：`ProductImageLoader` 重试时在 URL 追加 `?reload=N`，litbimg CDN 对任意 query 返回 403，导致点击「重试」必失败；改为仅用 `cachePolicy` 绕过缓存，URL 保持不变
- **并发限流**：新增 `ImageFetchLimiter`（最多 3 路并发），降低每页 30 张图同时请求触发的 CDN 限流
- **退避重试**：对 403/502/503 等状态码自动重试最多 3 次（250ms 递增延迟）
- **Accept 头**：改为只请求 `image/jpeg,image/png`，避免 CDN 返回 webp/avif 导致 `NSImage` 解码失败
- **Cookie**：启用 `HTTPCookieStorage.shared`，与浏览器行为一致
- **URL 规范化**：litbimg 域名去掉全部 query（不仅 `f=0`）
- **导入合并**：`pickBetterImageURL` 优先无 query、HTTPS 的图片链接

**涉及文件**

- `PLADashboard/Features/Dashboard/ProductImageLoader.swift`
- `PLADashboard/Features/Dashboard/ProductImageURLResolver.swift`
- `PLADashboard/Data/Database/ProductCatalogMerge.swift`
- `PLADashboard/Data/Database/DatabaseClient+Import.swift`
- `PLADashboardTests/ProductImageURLResolverTests.swift`
- `PLADashboardTests/ProductCatalogMergeTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/ProductImageURLResolverTests \
  -only-testing:PLADashboardTests/ProductCatalogMergeTests
# TEST SUCCEEDED
```

**下一步**

- 用户重新打开看板验证图片加载率；若仍大量失败，考虑导入时本地化缓存图片（方案 C）

### 2026-06-26 — litbimg CDN 图片 403 修复（方案 A+B）

**内容**

- `ProductImageURLResolver` 对 rightinthebox 域名去掉 `?f=0` 查询参数
- `ProductImageLoader` 为 rightinthebox 图片附加 Referer 与 Safari User-Agent
- `Info.plist` 为 litbimg / litb-cgis 配置 ATS HTTP 例外

**涉及文件**

- `PLADashboard/Features/Dashboard/ProductImageURLResolver.swift`
- `PLADashboard/Features/Dashboard/ProductImageLoader.swift`
- `PLADashboard/Info.plist`
- `PLADashboard.xcodeproj/project.pbxproj`
- `PLADashboardTests/ProductImageURLResolverTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/ProductImageURLResolverTests
# TEST SUCCEEDED
```

### 2026-06-26 — 修复大文件导入 staging 失败与中文报错

**内容**

- 根因：271MB UTF-8 TSV 在 staging 阶段 `Data(contentsOf:)` 整文件读入内存，且对容器内文件使用 `.withSecurityScope` 创建 bookmark 可能失败并抛出英文 "The file couldn't be opened."。
- 编码检测改为仅采样 64KB；已是 UTF-8 的大文件不再整文件读入。
- staging bookmark 改用 Apple 推荐的 `.minimalBookmark`（容器内文件无需 security scope）。
- 新增 `ImportUserFacingError`，将复制/编码/校验/书签各阶段错误映射为中文说明。

**涉及文件**

- `PLADashboard/Data/Import/ImportTextEncoding.swift`
- `PLADashboard/Data/Import/ImportStagingStore.swift`
- `PLADashboard/Data/Import/ImportUserFacingError.swift`
- `PLADashboard/Features/Imports/ImportViewModel.swift`
- `PLADashboard/App/RootView.swift`
- `PLADashboardTests/ImportTextEncodingTests.swift`
- `PLADashboardTests/ImportStagingStoreTests.swift`
- `PLADashboardTests/ImportUserFacingErrorTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/ImportTextEncodingTests \
  -only-testing:PLADashboardTests/ImportStagingStoreTests \
  -only-testing:PLADashboardTests/ImportUserFacingErrorTests
# TEST SUCCEEDED
```

**下一步**

- 使用真实 271MB TSV 在本机验证完整导入流程

### 2026-06-26 — 产品图加载诊断与 SHO 账户优化

**内容**

- **根因 1（数据层）**：Merchant 导入对 `S9730219` 类序号未剥离 `S` 前缀，图片落在 `S*` 产品行，Ads/看板使用数字 `product_id`，导致指标行无图或需合并。
- **根因 2（展示层）**：`AsyncImage` 无超时，CDN 慢挂起时一直显示转圈；部分自建站图片 URL 缺少 `https://` 前缀无法正确请求。
- **修复**：`ProductIDNormalizer.normalize` 识别 `S+数字`；新增 v5 迁移合并/重命名 S 前缀产品；`ProductImageURLResolver` 补全协议；`ProductImageLoader`（URLSession + 12s 超时 + 内存缓存）替代 `AsyncImage`。
- **诊断**：设置页「产品图」区可查看入库统计、缺图样例、S 前缀重复数，并手动触发合并。

**涉及文件**

- `PLADashboard/Data/Import/ProductIDNormalizer.swift`
- `PLADashboard/Data/Database/Migrations/Migration_v5_LsinProductIDReconciliation.swift`
- `PLADashboard/Data/Database/Migrations/DatabaseMigrator.swift`
- `PLADashboard/Data/Database/ProductCatalogMerge.swift`
- `PLADashboard/Data/Database/DatabaseClient.swift`
- `PLADashboard/Data/Database/DatabaseClient+Import.swift`
- `PLADashboard/Data/Database/DatabaseClient+ProductImageDiagnostics.swift`
- `PLADashboard/Data/Analytics/ProductPerformanceRowMapper.swift`
- `PLADashboard/Features/Dashboard/ProductImageURLResolver.swift`
- `PLADashboard/Features/Dashboard/ProductImageLoader.swift`
- `PLADashboard/Features/Dashboard/ProductImageView.swift`
- `PLADashboard/Features/Settings/ProductImageDiagnosticsSection.swift`
- `PLADashboard/Features/Settings/SettingsView.swift`
- `PLADashboardTests/ProductImageURLResolverTests.swift`
- `PLADashboardTests/ProductIDNormalizerTests.swift`
- `PLADashboardTests/LsinProductIDReconciliationTests.swift`

**验证结果**

```bash
xcodebuild -scheme PLADashboard -destination 'platform=macOS' test \
  -only-testing:PLADashboardTests/ProductImageURLResolverTests \
  -only-testing:PLADashboardTests/ProductIDNormalizerTests \
  -only-testing:PLADashboardTests/LsinProductIDReconciliationTests \
  -only-testing:PLADashboardTests/MerchantCenterImporterTests
# TEST SUCCEEDED
```

**下一步**

- 在 SHO 账户运行应用后于「设置 → 产品图」执行诊断；若仍有转圈，用浏览器/curl 验证 `litb-cgis.rightinthebox.com` 等域名在本机是否可达
