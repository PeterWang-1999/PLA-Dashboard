# PLA Dashboard

PLA Dashboard 是面向 Google Shopping 产品投放分析的 macOS 本地应用。它将 Merchant Center 商品资料、广告投放数据与 Product Sales 数据汇总到本地数据库，提供产品级指标、趋势、筛选和 CSV 导出。

## 下载与系统要求

- 最新安装包：`1.2 (4)`（GitHub 标签 `v1.2`）
- 系统要求：macOS 14.4 或更高版本
- 处理器：Apple Silicon 与 Intel Mac（Universal 2）
- 下载地址：[GitHub Releases](https://github.com/PeterWang-1999/PLA-Dashboard/releases/latest)

发布页提供两种安装包：

- `PLADashboard-macOS-Universal-v1.2.dmg`：打开镜像后将应用拖到“应用程序”。
- `PLADashboard-macOS-Universal-v1.2.zip`：解压后将 `PLA Dashboard.app` 拖到“应用程序”。

仓库 `main` 包含 1.2 之后的源码变更。对应的功能和修复见 [更新日志的未发布章节](CHANGELOG.md#未发布)。

## 安装与首次打开

1. 从 Release 页面下载 DMG 或 ZIP。
2. 若使用 DMG，双击挂载镜像；若使用 ZIP，双击解压。
3. 将应用拖入“应用程序”文件夹。
4. 在 Finder 的“应用程序”中按住 Control 点击“PLA Dashboard”，选择“打开”，并在确认框中再次选择“打开”。

当前发布包采用 ad-hoc 签名，尚未公证。若 macOS 阻止首次打开，请进入“系统设置 → 隐私与安全性”，确认应用来自 GitHub Releases 后选择“仍要打开”。可在发布资产列表核对文件的 SHA-256。

如系统仍提示文件已损坏，可在确认下载来源和 SHA-256 后执行：

```bash
xattr -dr com.apple.quarantine "/Applications/PLA Dashboard.app"
open "/Applications/PLA Dashboard.app"
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

1. **Merchant Center TSV**：支持中英文表头。必需字段为产品 ID（`序号` / `id`）、标题（`标题` / `title`）、商品链接（`canonical link` / `link`）和图片链接（`图片链接` / `image link`）；自定义标签 0–4 与商品类目为可选字段。标准商品 ID 的变体段可以包含数字或字母，例如 `13548439_0000G_US_en` 会归一为主产品 ID `13548439`。
2. **Google Ads 产品数据**：支持常见 CSV/制表符导出及 UTF-8、UTF-16 等编码。应用会扫描前 10 行自动识别表头，不要求表头固定在第一行或第三行。必需字段为 `天`、`产品 ID`、`广告系列`、`货币代码`、`费用`、`展示次数`、`点击次数`、`转化次数`、`转化价值`。

#### 自建站

1. **Merchant Center TSV**：必需字段为 `序号` / `id`、`标题` / `title`、`链接` / `link`、`图片链接` / `image link`。
2. **投放产品明细（CSV/XLSX）**：必需字段为 `日期`、`LSIN`、`Market Cost`、`Impressions`、`Clicks`、`Conversions`、`Conversion Value`；`首次上架时间` 与 `CMS3` 为可选字段。
3. **Product Sales CSV**：必需字段为 `日期`、`LSIN`、`Gross Sales($)`、`毛利额($)`。

导入结果会显示有效行、错误和警告；可导出错误与警告 CSV 进行修正。「导入历史」按数据源显示最近的批次。应用使用文件指纹防止重复写入。

### 3. 使用产品数据看板

- 搜索：按产品 ID 查询。
- 筛选：按自定义标签和类目缩小范围。
- 排序与分页：支持消费、ROI 等已接入后端排序的字段；菜单“看板”提供首页、上一页、下一页和尾页快捷操作。
- 产品明细：三方站账户可双击产品记录打开明细浮窗，也可选中记录后按 `Command-O` 或使用右键菜单；浮窗展示原始 SKU 维度的消费、ROI、点击和转化，并支持导出与访问落地页。自建站暂不提供此功能。
- 趋势：查看最近 6 个完整周及当前未完成周的消费/销售趋势；悬停柱形可查看周区间、合计和日均值。
- 导出：按当前筛选与排序条件导出 CSV，上限为 50,000 条产品记录，可选择是否包含点击与转化字段。
- 刷新：使用工具栏刷新，或按 `Shift-Command-R` 重建聚合并刷新看板。

指标表中的当前周按已导入日期参与消费、ROI、CPA、ARPU、CPC、CVR、AOS、点击与转化等展示。底栏会显示当前报告周期、当前周截止日和覆盖天数，避免把未完整周误读为整周。

### 4. 使用数据看板

进入侧边栏“数据看板”，可以在同一页面查看当前筛选范围内的核心指标、消费/销售/ROI 趋势、广告系列表现、类目效率分布和消费 Top 10 产品：

- 工具栏的产品 ID、自定义标签和类目条件会同步作用于整张看板。
- 趋势图支持周维度与日维度切换；悬停后显示当期消费、销售、ROI 及与上一周期的变化。
- 三方站账户会额外显示按消费降序排列的广告系列表现。
- 类目气泡图以横轴表示消费、纵轴表示 ROI、气泡大小表示销售额；悬停后可查看占比、效率指标与环比。
- 页面底部显示实际报告周期；系统启用“减少动态效果”或“降低透明度”时会自动采用相应呈现。

### 5. 设置与数据维护

- “设置”中可调整每页行数和 Ads 日表保留期限；账户级设置仅作用于当前账户。
- 产品数据页底栏的“数据维护”提供过期 Ads 数据清理、产品图数据诊断和 S 前缀产品记录合并。清理与合并前会显示确认提示。
- 从旧版升级到当前源码构建时，数据库迁移会清理旧预警标签历史。Merchant Center 自定义标签和「未匹配到 GMC 商品目录」提示继续提供。

### 6. 下载 BI Data 报表（自建站，开发分支）

在自建站的「数据下载」页点击「登录 BI Data…」，使用公司账号登录。应用识别到登录成功后会自动返回「数据下载」，并在当前自建站工作区保留会话。打开临时导出窗口或运行下载任务时，应用会自动进入「渠道投放分析」。如需切换报表地址，可在登录窗口点击「更改地址」。

可以用「临时导出」修改渠道投放分析的筛选，也可以在「编辑任务」中创建每日下载任务。每次定时触发或点击「立即运行」都会使用同一套预设下载渠道投放分析 CSV 和 Market Performance 投放产品明细 XLSX。投放产品明细属于 PLA 投放表现，合并任务使用 Google PLA 预设。内置预设按北京时间取过去 6 个完整周和本周，定时下载在应用运行期间执行。

两份报表各有一条下载记录，可分别查看进度、重试和打开文件。下载完成后可在 Finder 的「下载」中找到文件。打开以前下载的记录时，应用也会把文件复制到「下载」。

## 数据与隐私

- 导入文件会复制到应用容器，并写入当前账户的本地 SQLite 数据库。
- 应用不要求登录云端服务，账户数据不会由应用主动上传到本仓库或第三方服务器。
- 商品图片按 Merchant Center 中保存的图片 URL 联网加载；图片域名不可访问时会显示占位状态。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 导入数据 | `Shift-Command-I` |
| 刷新聚合 | `Shift-Command-R` |
| 查看选中产品明细（三方站） | `Command-O` |
| 首页 / 尾页 | `Option-Command-←` / `Option-Command-→` |
| 上一页 / 下一页 | `Command-←` / `Command-→` |
| 切换侧边栏 | `Control-Command-S`（macOS 系统命令） |

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

项目使用 SwiftUI、Observation、SQLite、GRDB.swift 和 App Sandbox。请使用完整的 Xcode 打开 `PLADashboard.xcodeproj`，选择共享的 `PLADashboard` 方案。若命令行默认使用 Command Line Tools，可为单次命令设置 `DEVELOPER_DIR`，指向本机 Xcode 的 `Contents/Developer`。

```bash
# 构建
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -destination 'platform=macOS' build

# 功能与性能回归（Debug）
xcodebuild -project PLADashboard.xcodeproj \
  -scheme PLADashboard \
  -destination 'platform=macOS' test
```

Release 性能测试命令和历史对照见 [性能基准](BenchmarkReport.md)。近期开发状态见 [开发进度](DEV_PROGRESS.md)。

## 许可证

当前仓库中的 PLA Dashboard 开源代码采用 [Apache License 2.0](LICENSE) 授权，版权归 Ziao Wang 所有。你可以在许可证约束下使用、修改和分发代码；重新分发时需保留许可证、版权与 [NOTICE](NOTICE) 声明。

第三方依赖仍分别遵循其自身的许可证。本许可证仅适用于当前仓库中明确发布的内容，不自动适用于其他私有仓库、未来闭源模块、商标、Logo 或独立商业服务。
