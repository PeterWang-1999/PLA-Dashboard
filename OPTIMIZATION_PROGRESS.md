# 分阶段优化进度

约定：每轮只修一个问题；完成代码和必要回归后，由用户本地构建验证。用户确认通过后才提交本轮文件，再进入下一问题。未确认前不提交，不推送。

## 第 1 阶段：多窗口导入与账户切换保护

状态：用户本地验证通过，已授权提交及推送。

- AccountStore 持有全窗口共享的导入令牌。在异步任务启动前申请，成功/失败/取消收尾后释放；旧令牌不能释放新任务。
- 切账户期间拒绝新导入，导入期间拒绝所有窗口的账户切换及第二次导入。新建账户可以继续，但导入期间不自动切换。
- ImportViewModel 校验工作区修订与操作令牌，忽略旧任务的进度、结果和回调；历史查询在账户重置后不提交旧结果。
- 保留数据库计算、标签规则及表格查询行为，本阶段没有速度提升承诺。

验证：2026-09-30，Xcode Debug/macOS 构建与定向测试成功，17 个测试通过（AccountStoreTests 16 个、ImportViewModelAccountResetTests 1 个），其中新增 4 个回归测试。Swift 语法检查及 git diff --check 通过。构建仍有既有 XCTest actor 隔离/Swift 6 迁移警告，当前 Swift 5 模式下未阻止构建。

测试日志：`/private/tmp/pla-phase1-outside-20260930.log`。独立 DerivedData：`/private/tmp/pla-phase1-outside-20260930`。未做真实双窗口 UI 验证。

本地验证步骤：

1. Xcode 打开 PLADashboard.xcodeproj，选择 PLADashboard/My Mac，构建运行。
2. 准备两个账户，通过“文件 → 新建窗口”打开两个窗口。在 A 窗口导入较大文件，B 窗口尝试切账户，应被拦截，账户不改变。
3. 导入期间，在 B 窗口尝试导入，应提示已有导入进行中，不启动第二个任务。
4. 在 A 取消导入，等收尾结束后，B 应能切账户；新账户不得出现 A 的导入进度或结果。
5. 正常完成一次导入后再切账户；再测试错误文件导入失败后切账户，保护均应解除。
6. 导入期间新建账户：新账户可创建，当前账户保持不变；完成后可正常切到新账户。

待确认后提交范围：AccountStore.swift、CreateAccountSheet.swift、RootView.swift、WorkspaceAccountError.swift、ImportViewModel.swift、AccountStoreTests.swift、本文。本次已有审查报告与 dist/.cursor 工作区变动不混入修复提交。

下一阶段候选：同账户内刷新过期结果保护。尚未开始。
