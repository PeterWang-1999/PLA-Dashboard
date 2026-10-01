# 第 6 阶段查询基线

日期：2026-10-01。macOS 实机 MacBook Air/arm64，Xcode-beta，Release 优化构建；测试命令临时开启 ENABLE_TESTABILITY，关闭代码覆盖率，未修改发布配置。

## 查询调度验证

新增可见页面回归测试确认：图表筛选后仅调用图表 loader，产品表 loader 调用为 0；图表设置更新及图表首屏就绪同样只加载图表。导入页不调用两种 loader，返回产品页后加载最新条件。这里统计的是高层查询请求，不能解释成单条 SQL 数量。

## 数据库工作量测量

同一应用版本、同一内存数据库：500 产品、10,000 投放明细，默认筛选。比较旧路径对应的额外工作量（产品表第一页 30 行 + 图表）与图表单独查询。预热 1 轮后，每组 11 样本，交替先后顺序；每次清空应用 dashboard 指标缓存，SQLite/系统缓存保留。

| 工作量 | p50 | p95 |
|---|---:|---:|
| 产品表 + 图表 | 75.936 ms | 81.298 ms |
| 仅图表 | 72.285 ms | 155.220 ms |

p50 略降；p95 在本次运行中更高，原因未定位，不能声称尾延迟改善。11 样本规模有限，p95 使用最近秩法，对应最大样本。该测量复现查询工作量，并非两次 app 版本的完整首屏对比；不包含造数、搜索防抖、导航、图片、SwiftUI 渲染、磁盘库和真实账户规模，因此不能当作用户实际页面加载速度或整体加速比例。

## 验证与来源

- Debug 构建及 50 项回归通过，0 失败/0 跳过；其中新增可见页面/共享数据通知测试 8 项。
- Release 基线测试通过。首次 Release 未开启 testability，测试目标导入失败；用临时构建设置修正后通过。第一次通过运行未提供可提取的 console log；随后以 XCTest 附件记录并提取上述测量。
- Debug 日志：`/private/tmp/pla-phase6-final-20261001.log`。
- Release 最终日志：`/private/tmp/pla-phase6-release-report-20261001.log`。
- Release 结果：`/private/tmp/pla-phase6-release-20261001/Logs/Test/Test-PLADashboard-2026.10.01_14-06-20-+0800.xcresult`。
- 原始计时附件：`/private/tmp/pla-phase6-measurements/129BB66C-4358-4BCA-B7D8-8464A054B432.txt`。
- 可复跑用例：`VisiblePageQueryBaselineTests/testChartOnlyVersusRedundantPageAndChartWorkload`。

## 下一步

保留本基线用于后续查询优化对照。下一阶段针对三方站预警筛选/分页的全候选扫描建立 1k/10k 产品查询基线，再考虑受数据修订和设置快照控制的缓存。完整界面响应仍需 Release SwiftUI/Time Profiler 实际交互录制；本轮没有 Instruments trace。
