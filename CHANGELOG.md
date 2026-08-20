# Changelog

本文件记录 PLA Dashboard 的重要变更。

## 2026-08-20

### 改进

- 产品数据表仅为后端完整支持的“消费”和“ROI”保留列头排序，其他指标改为不可排序列，避免显示与实际排序字段不一致。
- 产品数据表改为逐单元格提供 VoiceOver 描述，包含列名、当前值、相对整体变化或周趋势，不再在每个单元格重复朗读整行摘要。
- 恢复 `NavigationSplitView` 提供的系统侧边栏切换项，保留标准 macOS 工具栏布局和交互。
- 将“重新计算预警标签”“重置预警标签历史”和“清理过期 Ads 数据”从设置窗口移到产品数据页面底栏的“数据维护”菜单。
- 设置窗口仅保留偏好值；数据维护操作继续提供范围说明、破坏性确认和完成结果反馈。

### 验证

- 通过 macOS 14.4 部署目标的 Xcode 构建。
- 排序、账户设置、设置通知和标签状态机相关测试共 26 项通过。

### 已知问题

- `SettingsPerAccountTests.testRetentionPurgeUsesScopedSettings()` 在当前 Xcode-beta/macOS 27 测试宿主中发生测试进程崩溃，单独运行仍可复现，未产生断言失败。
- Xcode 仍报告项目原有的 `Info.plist` Copy Bundle Resources 警告。
