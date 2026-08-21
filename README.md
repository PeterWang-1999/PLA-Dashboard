# PLA Dashboard

PLA Dashboard 是面向 Google Shopping 产品投放分析的 macOS 本地应用。它将 Merchant Center 商品资料、广告投放数据与 Product Sales 数据汇总到本地数据库，提供产品级指标、趋势、筛选、预警标签和 CSV 导出。

## 下载与系统要求

- 最新版本：`1.1 (2)`
- 系统要求：macOS 14.4 或更高版本
- 处理器：Apple Silicon 与 Intel Mac（Universal 2）
- 下载地址：[GitHub Releases](https://github.com/PeterWang-1999/PLA-Dashboard/releases/latest)

发布页提供两种安装包：

- `PLADashboard-macOS-Universal-v1.1.dmg`：推荐，打开后将 `PLADashboard.app` 拖到“应用程序”。
- `PLADashboard-macOS-Universal-v1.1.zip`：解压后将 `PLADashboard.app` 拖到“应用程序”。

## 安装与首次打开

1. 从 Release 页面下载 DMG 或 ZIP。
2. 若使用 DMG，双击挂载镜像；若使用 ZIP，双击解压。
3. 将 `PLADashboard.app` 拖入“应用程序”文件夹。
4. 在 Finder 的“应用程序”中按住 Control 点击 `PLADashboard`，选择“打开”，并在确认框中再次选择“打开”。

当前发布包采用本地 ad-hoc 签名，未使用 Developer ID 签名和 Apple 公证。若 macOS 阻止首次打开，请进入“系统设置 → 隐私与安全性”，确认应用来源后选择“仍要打开”。请只使用本仓库 Release 页面提供的文件，并在发布说明中核对 SHA-256。

如系统仍提示文件已损坏，可在确认下载来源和 SHA-256 后执行：

```bash
xattr -dr com.apple.quarantine /Applications/PLADashboard.app
open /Applications/PLADashboard.app
```

公司设备可能受 MDM 或安全策略限制；这种情况下需要联系设备管理员放行未公证应用。

## 快速开始

### 1. 创建账户

首次启动后，在窗口左下角打开账户菜单，选择“新建账户…”，输入账户名称并选择类型：

- 三方站：使用 Merchant Center TSV 与 Google Ads 产品数据。
- 自建站：使用 Merchant Center TSV、投放产品明细，以及可选的 Product Sales CSV。

不同账户使用独立的本地数据库、导入历史和偏好设置。导入进行中不能切换账户。

### 2. 导入数据

进入侧边栏“数据导入”，先选择数据源，再选择文件。建议先导入 Merchant Center 商品资料，再导入投放和销售数据。每个数据源都可以先点“导入样例文件”检查格式。

#### 三方站

1. **Merchant Center TSV**：支持中英文表头。必需字段为产品 ID（`序号` / `id`）、标题（`标题` / `title`）、商品链接（`canonical link` / `link`）和图片链接（`图片链接` / `image link`）；自定义标签 0–4 与商品类目为可选字段。
2. **Google Ads 产品数据**：支持常见 CSV/制表符导出及 UTF-8、UTF-16 等编码。应用会扫描前 10 行自动识别表头，不要求表头固定在第一行或第三行。必需字段为 `天`、`产品 ID`、`广告系列`、`货币代码`、`费用`、`展示次数`、`点击次数`、`转化次数`、`转化价值`。

#### 自建站

1. **Merchant Center TSV**：必需字段为 `序号` / `id`、`标题` / `title`、`链接` / `link`、`图片链接` / `image link`。
2. **投放产品明细（CSV/XLSX）**：必需字段为 `日期`、`LSIN`、`Market Cost`、`Impressions`、`Clicks`、`Conversions`、`Conversion Value`；`首次上架时间` 与 `CMS3` 为可选字段。
3. **Product Sales CSV**：必需字段为 `日期`、`LSIN`、`Gross Sales($)`、`毛利额($)`。

导入结果会显示有效行、无效行和错误信息；可导出错误 CSV 进行修正。重复导入同一文件时，应用会依据文件指纹避免重复写入。

### 3. 使用产品数据看板

- 搜索：按产品 ID 查询。
- 筛选：按预警标签、自定义标签和类目缩小范围。
- 排序与分页：支持消费、ROI 等已接入后端排序的字段；菜单“看板”提供首页、上一页、下一页和尾页快捷操作。
- 趋势：查看最近 6 个完整周及当前未完成周的消费/销售趋势；悬停柱形可查看周区间、合计和日均值。
- 导出：导出当前筛选与排序条件下的 CSV，可选择是否包含点击与转化字段。
- 刷新：使用工具栏刷新，或按 `Shift-Command-R` 重建聚合并刷新看板。

指标表中的当前周按已导入日期参与消费、ROI、CPA、ARPU、CPC、CVR、AOS、点击与转化等展示；预警标签仍使用完整周口径。底栏会显示当前报告周期、当前周截止日和覆盖天数，避免把未完整周误读为整周。

### 4. 设置与数据维护

- “设置”中可调整每页行数、预警阈值和 Ads 日表保留期限；账户级设置仅作用于当前账户。
- 产品数据页底栏的“数据维护”可重新计算预警标签、重置标签历史或清理当前账户的过期 Ads 日表。
- 重置标签历史和清理数据属于破坏性操作，应用会先显示影响范围并要求确认。

## 数据与隐私

- 导入文件会复制到应用容器，并写入当前账户的本地 SQLite 数据库。
- 应用不要求登录云端服务，账户数据不会由应用主动上传到本仓库或第三方服务器。
- 商品图片按 Merchant Center 中保存的图片 URL 联网加载；图片域名不可访问时会显示占位状态。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 导入数据 | `Shift-Command-I` |
| 刷新聚合 | `Shift-Command-R` |
| 首页 / 尾页 | `Option-Command-←` / `Option-Command-→` |
| 上一页 / 下一页 | `Command-←` / `Command-→` |
| 切换侧边栏 | `Control-Command-S` |

## 常见问题

**导入时提示缺少必需列**

先使用“导入样例文件”比对表头。列名会去除 BOM 和首尾空格，但业务字段名仍需与上述要求一致。

**Google Ads 文件扩展名是 CSV，但实际由制表符分隔**

应用会自动检测逗号或制表符分隔，并自动识别表头位置，无需手工转换。

**看板没有数据或数字没有更新**

确认当前账户已同时导入 Merchant 商品数据和对应的投放数据，然后点击“刷新聚合”。还需检查产品 ID/LSIN 是否能在不同数据源间对齐。

**图片持续加载或无法显示**

检查 Merchant 文件的图片链接是否完整，并确认本机网络可以访问对应图片域名。

## 开发与验证

技术栈：SwiftUI、Observation、SQLite、GRDB.swift、App Sandbox。

```bash
# 构建
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -destination 'platform=macOS' build

# 功能与性能回归（Debug，含 10k 行基准）
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -destination 'platform=macOS' test

# Release 性能 Test Plan
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -testPlan PLADashboard.xcodeproj/xcshareddata/xctestplans/PLADashboardPerformance.xctestplan \
  -configuration Release \
  -destination 'platform=macOS' test
```

性能基准详见 [BenchmarkReport.md](BenchmarkReport.md)，版本变更详见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

当前仓库中的 PLA Dashboard 开源代码采用 [Apache License 2.0](LICENSE) 授权，版权归 Ziao Wang 所有。你可以在许可证约束下使用、修改和分发代码；重新分发时需保留许可证、版权与 [NOTICE](NOTICE) 声明。

第三方依赖仍分别遵循其自身的许可证。本许可证仅适用于当前仓库中明确发布的内容，不自动适用于其他私有仓库、未来闭源模块、商标、Logo 或独立商业服务。
