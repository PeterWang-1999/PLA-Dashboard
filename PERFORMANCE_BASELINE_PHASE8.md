# 第 8 阶段图表 SQL 汇总基线

2026-10-01，MacBook Air/arm64，Release 优化构建。仅本次测试命令开启 testability，关闭代码覆盖率。

## 改动与对账

周趋势使用 SQL SUM，Top 10 在每 500 产品批次中 SQL GROUP BY/LIMIT 10 后合并候选。无需读取全部 ProductWeeklyMetricsRecord 或在 Swift 中为所有产品累计排序。产品集合、金额与比率口径保持一致。

Debug 37 项回归通过。新增 1,001 产品、多个周、默认/ROI 升序排序用例，以既有逐周记录接口为独立计算对照，验证消费/销售/ROI/CVR/CPC/AOS、Top 10 身份与完整指标以及跨批次同花费次序；保留 50,001 产品与导出上限边界。

## Release 查询工作量

500 产品、10,000 投放明细，默认筛选，同一内存数据库。预热 1 轮，每组 11 样本，交替工作量次序并清空应用 dashboard 缓存；SQLite/系统缓存仍保留。p95 最近秩法对应最大样本。

| 工作量 | p50 | p95 |
|---|---:|---:|
| 本轮仅图表 | 75.155 ms | 79.504 ms |
| 上轮仅图表 | 78.958 ms | 80.941 ms |
| 本轮产品表 + 图表（额外工作量对照） | 79.656 ms | 83.307 ms |

上下两轮是不同时间的测试运行，样本有限，也未隔离其它系统负载。数值显示轻微改善，不能推导稳定加速比例；不含造数、图片、渲染、搜索防抖或磁盘库。对大量产品/周记录的主要结构性收益是减少记录物化与 Swift 分组，尚未测量真实大账户峰值内存。

## 来源与后续

- Debug：`/private/tmp/pla-phase8-final-20261001.log`。
- Release：`/private/tmp/pla-phase8-release-20261001.log`。
- 原始附件：`/private/tmp/pla-phase8-measurements/D70925C1-B994-457B-8BCF-BBBEDFD3BC43.txt`。
- Release 结果：`/private/tmp/pla-phase6-release-20261001/Logs/Test/Test-PLADashboard-2026.10.01_14-49-05-+0800.xcresult`。

仍待定位/优化：图表日趋势与广告系列的事实去重查询、全量产品身份读取，以及图片缩略/缓存。完整页面体验需真实账户 Release Instruments 测量；本轮没有 trace。
