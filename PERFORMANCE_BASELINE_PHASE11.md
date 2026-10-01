# 阶段 11：产品页面计数复用

相同筛选条件翻页或改变消费/ROI 排序时，复用最近一次产品总数，避免再次 GROUP BY 全部报告周指标。缓存由 DatabaseClient actor 持有，仅一个条目；筛选与报告周变化重新计数；现有 invalidateDashboardCache 清理计数。另检查同一 SQLite 连接 total_changes() 及其他连接提交的 PRAGMA data_version，防止写入后继续使用旧计数。当前页产品、周指标及行转换仍实时执行，不缓存页面结果。

## Release 测量

同一机器、40,000 投放事实、2,000 产品、每页 30 行、内存数据库。每场景预热后 11 个样本。以下为暖查询（包括查询及行转换），不是首次启动、真实磁盘或 SwiftUI/图片渲染。前后为独立测试运行，并非配对同进程测量，环境噪声仍可能影响结果。

| 场景 | 原实现 p50/p95 ms | 计数复用 p50/p95 ms |
|---|---:|---:|
| 重复第一页 | 6.041 / 7.327 | 5.227 / 5.630 |
| 第 30 页 | 7.512 / 7.727 | 6.561 / 6.872 |
| 自定义标签 EN | 9.484 / 9.693 | 6.721 / 7.041 |
| 产品 ID 搜索 | 0.983 / 1.245 | 0.931 / 0.948 |

ROI 降序暖查询新实现 p50/p95 5.039/5.188ms，未取得相同原实现排序场景的基线，不能据此宣称改善。首次筛选仍执行计数，不保证上述收益。拒绝的 COUNT(*) OVER() 合并方案在普通页面/翻页测试中变慢，最终代码未保留。

原始附件：`/private/tmp/pla-page-before-attachments/07CBC519-56A9-4243-8D1F-0B8E89A0CC71.txt`、`/private/tmp/pla-page-cache-attachments/D2FD180B-8E02-49FD-BDBD-D788B5DB97E4.txt`。

## 验证及边界

Release 最终 14 个测试通过：DashboardPageLoadPerformanceTests 3、DashboardFilterTests 7、ImportFinishTests 4。覆盖四种排序分页拼接与全量结果逐字段一致、空搜索、跨连接导入产品后计数 40→80/页数更新，以及筛选和导入回归。最终日志 `/private/tmp/pla-page-cache-verified.log`。

工作区文件读取发生超时，构建及测试使用 GitHub 同一 HEAD 13d2be3 的临时副本 `/private/tmp/pla-page-validation-github`，仅替换本轮 3 个文件；最终文件已复制回工作区并逐字节核对，临时副本 git diff --check 通过。没有实际 UI 渲染耗时捕获，不能把查询收益当作整页加载收益。

用户已确认本地验证通过并授权提交推送。因原工作区 Git/文件读取仍等待，提交由上述已测试副本执行；原工作区 Git 状态同步另行核对。
